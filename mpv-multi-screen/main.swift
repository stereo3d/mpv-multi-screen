//
// by Alaric Hamacher. 2025

//  Play multiple instances of MPV player, fullscreen across multiple screens
//
//------------------------------------------------------------------------------
import Foundation
import AppKit

//------------------------------------------------------------------------------
// Determine mpv executable path for later use
let mpvExecutable: String = {
    if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mpv") {
        return "/opt/homebrew/bin/mpv"
    } else {
        return "/usr/bin/env" // fallback to PATH
    }
}()

// Persistent config location: ~/Library/Application Support/mpv-multi-screen/audio.conf
let audioConfigPath: String = {
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/mpv-multi-screen")
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
    return base.appendingPathComponent("audio.conf").path
}()

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
    task.standardError = pipe
    do { try task.run() } catch { return "" }
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

// Returns array of (token, fullLine) for mpv audio devices.
// token is what you pass to --audio-device=<token>.
func mpvAudioDevices() -> [(String, String)] {
    let out = runMPVAndCapture(["--audio-device=help"])
    var result: [(String, String)] = []
    for raw in out.split(separator: "\n") {
        let fullLine = String(raw)
        let line = fullLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { continue }
        var token: String? = nil

        // Prefer token inside single quotes: 'token with spaces'
        if let firstQ = line.firstIndex(of: "'") {
            let afterFirst = line.index(after: firstQ)
            if let secondQ = line[afterFirst...].firstIndex(of: "'") {
                token = String(line[afterFirst..<secondQ])
            }
        }
        // Fallback: first whitespace-separated field
        if token == nil {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let first = parts.first {
                token = String(first)
            }
        }
        if let t = token, !t.isEmpty {
            result.append((t, fullLine))
        }
    }
    return result
}

//------------------------------------------------------------------------------
// Handle "list" command to show audio devices
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
    print("Use: mpv-multi-screen setaudio <idx1> <idx2> ... (one per screen, in order)")
    exit(0)
}

// Handle "setaudio" command to save per-screen audio devices by index
if CommandLine.argc > 1 && CommandLine.arguments[1] == "setaudio" {
    let devices = mpvAudioDevices()
    if devices.isEmpty {
        print("No audio devices reported by mpv.")
        exit(1)
    }
    let idxArgs = Array(CommandLine.arguments.dropFirst(2))
    if idxArgs.isEmpty {
        print("Usage: mpv-multi-screen setaudio <idx1> <idx2> ...")
        exit(2)
    }
    var chosen: [String] = []
    for s in idxArgs {
        if let n = Int(s), n >= 0, n < devices.count {
            chosen.append(devices[n].0) // token
        } else {
            print("Invalid index: \(s). Run 'mpv-multi-screen list' to see valid indexes.")
            exit(3)
        }
    }
    let payload = chosen.joined(separator: "\n") + "\n"
    do {
        try payload.write(to: URL(fileURLWithPath: audioConfigPath), atomically: true, encoding: .utf8)
        print("Saved \(chosen.count) audio device(s) → \(audioConfigPath)")
        exit(0)
    } catch {
        print("Failed to write audio config: \(error)")
        exit(4)
    }
}

if (CommandLine.argc - 1) != NSScreen.screens.count {
    print("Number of files does not match number of screens\n")
    exit(0)
}

//------------------------------------------------------------------------------
let screenIDs: [Int] = NSScreen.screens.compactMap {
    ( $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber )?.intValue
}

// Optional per-screen audio output devices (fallback if no saved config).
// Run `mpv --audio-device=help` to list valid device tokens.
let audioDevicesPerScreen: [String] = [
    // "auto",
    // "coreaudio/USB PnP Sound Device",
    // "coreaudio/HDMI"
]

// Load saved audio device tokens (one per line)
let savedAudioDevices: [String] = {
    if FileManager.default.fileExists(atPath: audioConfigPath),
       let text = try? String(contentsOfFile: audioConfigPath, encoding: .utf8) {
        return text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    return []
}()

//------------------------------------------------------------------------------
// get files
var files = [String]()
for i in 1...Int(CommandLine.argc - 1) {
    files.append(CommandLine.arguments[i])
}

//------------------------------------------------------------------------------
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

//------------------------------------------------------------------------------
// Run MPV
for (idx, file) in files.enumerated() {
    guard idx < screenIDs.count else { break }

    var args: [String] = [
        "--fs",                    // fullscreen
        "--screen=\(idx)",         // which display (0-based)
        "--loop",                  // loop playlist
        "--no-terminal",           // suppress terminal UI
        "--no-config",             // ignore user config for consistency
        "--no-osc"                 // hide on-screen controls
    ]

    // Assign per-screen audio device (prefer saved config; fallback to static array)
    if idx < savedAudioDevices.count {
        args.append("--audio-device=\(savedAudioDevices[idx])")
    } else if idx < audioDevicesPerScreen.count {
        args.append("--audio-device=\(audioDevicesPerScreen[idx])")
    }

    args.append(file)

    print("[mpv-multi-screen] launching MPV on screen \(idx+1) with file \(file)")
    shell(args)
    Thread.sleep(forTimeInterval: 0.4) // stagger launches a bit
}
