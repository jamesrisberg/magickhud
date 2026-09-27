import Foundation
import HUDKit
import magickHUDKit

// `magickhud <command> [key=value ...]`: talks to magickHUD's MacHUD control socket.
//
//   magickhud drop ~/Desktop/*.png                 # into the drop zone
//   magickhud run resize ~/Desktop/a.png width=800 wait=1
//   magickhud run web                              # every dropped image
//   magickhud jobs
//   magickhud presets
//   magickhud watch

let usage = """
usage: magickhud <command> [key=value ...]
  hello | state | help | quit
  panel show|hide|toggle id=tools
  panel frame id=tools x= y= w= h=
  panel mode id=tools full|compact|parked
  drop <file> ... [show=1]            add images to the drop zone (folders add the images inside)
  run <preset> [<file> ...] [field=value ...] [output=<template>] [wait=1] [show=1]
                                      without files, runs on the dropped images;
                                      wait=1 replies when the job is finished
  jobs [id=]                          jobs, newest first, with per-file status
  cancel [id=]                        cancel one job, or every running job
  presets [query=]                    presets and their fields
  files                               the dropped images with format, size, bytes
  clear                               empty the drop zone
  snapshot path=<png> [preset=]       write a PNG of the panel
  action <verb> [k=v ...]             the long form of the above
  settings get [key=]  |  settings set key=value ...  |  settings schema
  watch [events=state]                stream events (Ctrl-C to stop)

Paths travel as pipe-separated, percent-encoded lists (`action drop paths=`); this tool encodes
the files you name. Environment: MAGICKHUD_SOCKET picks the socket name (default magickhud).

"""

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "ctl" { arguments.removeFirst() }
guard let command = arguments.first, !["-h", "--help"].contains(command) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(arguments.isEmpty ? 2 : 0)
}

let socketName = ProcessInfo.processInfo.environment["MAGICKHUD_SOCKET"].flatMap { $0.isEmpty ? nil : $0 } ?? "magickhud"
let path = HUDSocket.path(for: socketName)

func fail(_ message: String, status: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("magickhud: \(message)\n".utf8))
    exit(status)
}

/// Absolute path for a file argument.
func absolute(_ file: String) -> String {
    let expanded = (file as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") { return (expanded as NSString).standardizingPath }
    return ((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded) as NSString).standardizingPath
}

let shorthands: Set<String> = ["drop", "run", "jobs", "cancel", "presets", "files", "clear", "snapshot"]
if shorthands.contains(command) {
    var rest = Array(arguments.dropFirst())
    var extra: [String] = []
    switch command {
    case "drop":
        let files = rest.filter { !$0.contains("=") || FileManager.default.fileExists(atPath: absolute($0)) }
        rest.removeAll { files.contains($0) }
        if files.isEmpty, !rest.contains(where: { $0.hasPrefix("paths=") }) { fail("drop needs files") }
        if !files.isEmpty { extra.append("paths=" + HUDDrop.encode(files.map { URL(fileURLWithPath: absolute($0)) })) }
    case "run":
        guard let preset = rest.first, !preset.contains("=") else { fail("run needs a preset, e.g. `magickhud run resize a.png width=800`") }
        rest.removeFirst()
        extra.append("preset=\(preset)")
        let files = rest.filter { !$0.contains("=") || FileManager.default.fileExists(atPath: absolute($0)) }
        rest.removeAll { files.contains($0) }
        // input=<path> is one plain path here; the socket expects the encoded list.
        var inputs = files.map(absolute)
        if let i = rest.firstIndex(where: { $0.hasPrefix("input=") }) {
            inputs.append(absolute(String(rest.remove(at: i).dropFirst("input=".count))))
        }
        if !inputs.isEmpty { extra.append("input=" + HUDDrop.encode(inputs.map(URL.init(fileURLWithPath:)))) }
        if let i = rest.firstIndex(where: { $0.hasPrefix("snapshot=") }) { rest.remove(at: i) }
    case "snapshot":
        if let i = rest.firstIndex(where: { $0.hasPrefix("path=") }) {
            rest[i] = "path=" + absolute(String(rest[i].dropFirst("path=".count)))
        }
    default:
        break
    }
    arguments = ["action", "name=\(command)"] + extra + rest
} else if command == "settings", arguments.count > 1, ["get", "set", "schema"].contains(arguments[1]) {
    // Send the sub-verb as `action=` so it is not read as a setting named "_".
    arguments[1] = "action=\(arguments[1])"
} else if command == "action", arguments.count > 1, !arguments[1].contains("=") {
    arguments[1] = "name=\(arguments[1])"
}

if command == "watch" {
    let args = HUDSocketClient.parseArguments(Array(arguments.dropFirst()))
    do {
        _ = try HUDSocketClient(path: path).subscribe(
            events: args["events"].map { $0.split(separator: ",").map(String.init) },
            onEvent: { event in
                if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) {
                    print(String(decoding: data, as: UTF8.self))
                    fflush(stdout)
                }
            },
            onClose: { exit(0) }
        )
    } catch {
        fail("magickHUD is not running (\(error))", status: 1)
    }
    dispatchMain()
}

exit(HUDSocketClient.runCLI(path: path, arguments: arguments, appName: "magickhud"))
