//
//  Play multiple instances of MPV player, fullscreen across multiple screens
//
//------------------------------------------------------------------------------
import Foundation
import AppKit

//------------------------------------------------------------------------------
if (CommandLine.argc - 1) != NSScreen.screens.count {
    print("Number of files does not match number of screens\n")
    exit(0)
}

//------------------------------------------------------------------------------
let screenIDs: [Int] = NSScreen.screens.compactMap {
    ( $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber )?.intValue
}

// Optional per-screen audio output devices (in screen order).
// Run `mpv --audio-device=help` to list valid device names.
let audioDevicesPerScreen: [String] = [
    // "auto",
    // "coreaudio/USB PnP Sound Device",
    // "coreaudio/HDMI"
]

//------------------------------------------------------------------------------
// get files
var files = [String]()
for i in 1...Int(CommandLine.argc - 1) {
    files.append(CommandLine.arguments[i])
}

//------------------------------------------------------------------------------
func shell(_ args: [String]) {
    let task = Process()
    // Prefer env-based resolution so PATH is honored; fall back to a common Homebrew path.
    if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mpv") {
        task.launchPath = "/opt/homebrew/bin/mpv"
        task.arguments = args
    } else {
        task.launchPath = "/usr/bin/env"
        task.arguments = ["mpv"] + args
    }
    task.launch()
}

//------------------------------------------------------------------------------
// Run MPV
for (idx, file) in files.enumerated() {
    guard idx < screenIDs.count else { break }

    var args: [String] = [
        "--fs",                    // fullscreen
        "--screen=\(idx)",         // which display
        "--loop",                  // loop playlist
        "--no-terminal",           // suppress terminal UI
        "--no-config"              // ignore user config for consistency
    ]

    // If you want to hide the OSC (on-screen controls):
    args.append("--no-osc")

    // Assign per-screen audio device if provided
    if idx < audioDevicesPerScreen.count {
        args.append("--audio-device=\(audioDevicesPerScreen[idx])")
    }

    args.append(file)

    print("[mpv-multi-screen] launching MPV on screen \(idx+1) with file \(file)")
    shell(args)
    Thread.sleep(forTimeInterval: 0.4) // stagger launches a bit
}
