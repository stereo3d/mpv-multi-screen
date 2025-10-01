//
//  mpv-multi-screen — launch one mpv instance per display, with optional per-screen audio routing
//  by Alaric Hamacher, 2025
//
//--------------------------------------------------------------------------------
import Foundation
import AppKit

//--------------------------------------------------------------------------------
// Resolve mpv executable once. Prefer Homebrew paths; fall back to PATH via /usr/bin/env.
let mpvExecutable: String = {
    let candidates = ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv"]
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
        return path
    }
    return "/usr/bin/env" // use PATH resolution
}()

// Persistent config: ~/Library/Application Support/mpv-multi-screen/audio.conf
let audioConfigPath: String = {
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/mpv-multi-screen")
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
    return base.appendingPathComponent("audio.conf").path
}()

//--------------------------------------------------------------------------------
// Helpers
@discardableResult
func runMPVAndCapture(_ args: [String]) -> String {
    let task = Process()
    if mpvExecutable == "/usr/bin/env" {
        task.launchPath = mpvExecutable
        task.arguments = ["mpv"] + args
    } else {
        task.launchPath = mpvExecutable
        task.arguments = args
    }
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError  = pipe
    do { try task.run() } catch { return "" }
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func shell(_ args: [String]) {
    let task = Process()
    if mpvExecutable == "/usr/bin/env" {
        task.launchPath = mpvExecutable
        task.arguments = ["mpv"] + args
    } else {
        task.launchPath = mpvExecutable
        task.arguments = args
    }
    task.launch()
}

// Parse `mpv --audio-device=help` lines and return (token, fullLine).
// Token is what mpv expects in --audio-device=<token>. Prefer the quoted token.
func mpvAudioDevices() -> [(String, String)] {
    let out = runMPVAndCapture(["--audio-device=help"])
    var result: [(String, String)] = []
    for raw in out.split(separator: "\n") {
        let fullLine = String(raw)
        let line = fullLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { continue }
        var token: String? = nil
        if let firstQ = line.firstIndex(of: "'") {
            let afterFirst = line.index(after: firstQ)
            if let secondQ = line[afterFirst...].firstIndex(of: "'") {
                token = String(line[afterFirst..<secondQ])
            }
        }
        if token == nil {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let first = parts.first { token = String(first) }
        }
        if let t = token, !t.isEmpty { result.append((t, fullLine)) }
    }
    return result
}

// Expand folders into playable files; accept files as-is.
let videoExts: Set<String> = [
    "mp4","mov","m4v","mkv","avi","wmv","flv","ts","mts","m2ts","webm","m2v","m1v"
]

func isDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    return exists && isDir.boolValue
}

func expandMedia(from path: String) -> [String] {
    let p = (path as NSString).expandingTildeInPath
    if isDirectory(p) {
        let url = URL(fileURLWithPath: p)
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return items
            .filter { videoExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { $0.path }
    } else {
        return [URL(fileURLWithPath: p).path]
    }
}

//--------------------------------------------------------------------------------
// Subcommands
if CommandLine.argc > 1 && CommandLine.arguments[1] == "list" {
    let devices = mpvAudioDevices()
    if devices.isEmpty {
        print("No audio devices reported by mpv.")
        exit(1)
    }
    for (i, dev) in devices.enumerated() {
        print("[\(i)] \(dev.1)")
    }
    print("\nConfig will be saved to: \(audioConfigPath)")
    print("Use: mpv-multi-screen setaudio <idx[,vol]> <idx[,vol]> ...  (one per screen, in order; vol = 0–100)")
    exit(0)
}

if CommandLine.argc > 1 && CommandLine.arguments[1] == "setaudio" {
    let devices = mpvAudioDevices()
    if devices.isEmpty {
        print("No audio devices reported by mpv.")
        exit(1)
    }
    let idxArgs = Array(CommandLine.arguments.dropFirst(2))
    if idxArgs.isEmpty {
        print("Usage: mpv-multi-screen setaudio <idx[,vol]> <idx[,vol]> ...")
        print("Example: mpv-multi-screen setaudio 12,100 13,45   # screen1→device#12@100%, screen2→device#13@45%")
        exit(2)
    }

    struct Choice { let token: String; let volume: Int? }
    var chosen: [Choice] = []

    for arg in idxArgs {
        // Accept formats: "12" or "12,80"
        let parts = arg.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
        guard let idxVal = Int(parts[0]), idxVal >= 0, idxVal < devices.count else {
            print("Invalid index: \(arg). Run 'mpv-multi-screen list' to see valid indexes.")
            exit(3)
        }
        var vol: Int? = nil
        if parts.count == 2 {
            guard let v = Int(parts[1]), (0...100).contains(v) else {
                print("Invalid volume in '\(arg)'. Volume must be 0–100.")
                exit(4)
            }
            vol = v
        }
        chosen.append(Choice(token: devices[idxVal].0, volume: vol))
    }

    // Write config as lines: <token>\t<volume or empty>
    let payload = chosen.map { c in
        if let v = c.volume { return "\(c.token)\t\(v)" }
        else { return "\(c.token)\t" }
    }.joined(separator: "\n") + "\n"

    do {
        try payload.write(to: URL(fileURLWithPath: audioConfigPath), atomically: true, encoding: .utf8)
        print("Saved \(chosen.count) audio device(s) → \(audioConfigPath)")
        exit(0)
    } catch {
        print("Failed to write audio config: \(error)")
        exit(5)
    }
}

//--------------------------------------------------------------------------------
// Validate arguments for playback
let screenCount = NSScreen.screens.count
let argCount = Int(CommandLine.argc - 1)
guard argCount == screenCount else {
    print("You passed \(argCount) path(s) for \(screenCount) screen(s).")
    print("Pass exactly one path per screen (each can be a file or a folder).")
    exit(5)
}

// Build per‑screen media lists
var mediaLists: [[String]] = []
for i in 1...argCount {
    mediaLists.append(expandMedia(from: CommandLine.arguments[i]))
}

// Collect per‑screen audio device tokens (and optional volumes) from audio.conf.
// Each line: <token>\t<volume?>   where volume is 0–100 (optional).
let savedAudio: [(token: String, volume: Int?)] = {
    guard FileManager.default.fileExists(atPath: audioConfigPath),
          let text = try? String(contentsOfFile: audioConfigPath, encoding: .utf8) else {
        return []
    }
    var out: [(String, Int?)] = []
    for raw in text.split(separator: "\n") {
        let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { continue }
        let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        let token = parts.count > 0 ? String(parts[0]) : ""
        var vol: Int? = nil
        if parts.count == 2 {
            let vstr = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if let v = Int(vstr), (0...100).contains(v) { vol = v }
        }
        if !token.isEmpty { out.append((token, vol)) }
    }
    return out
}()

// Optional static fallback (only used if no saved token for that screen)
let audioDevicesPerScreen: [String] = [
    // e.g. "coreaudio/HDMI"
]

//--------------------------------------------------------------------------------
// Launch one mpv per screen
for (idx, list) in mediaLists.enumerated() {
    guard idx < screenCount else { break }
    guard !list.isEmpty else { continue }

    var args: [String] = [
        "--fs",
        "--screen=\(idx)",          // 0-based display index
        "--loop-playlist=inf",      // loop the ENTIRE playlist
        "--no-terminal",
        "--no-config",
        "--no-osc"
    ]

    // Per-screen audio routing (prefer saved config; fallback to static array)
    if idx < savedAudio.count {
        args.append("--audio-device=\(savedAudio[idx].token)")
        if let vol = savedAudio[idx].volume {
            args.append("--volume=\(vol)")
        }
    } else if idx < audioDevicesPerScreen.count {
        args.append("--audio-device=\(audioDevicesPerScreen[idx])")
    }

    // Append all media for this screen
    args.append(contentsOf: list)

    print("[mpv-multi-screen] Screen \(idx+1): launching mpv with \(list.count) item(s)")
    shell(args)
    Thread.sleep(forTimeInterval: 0.4) // small stagger between instances
}
