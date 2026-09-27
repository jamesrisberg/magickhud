import AppKit
import HUDKit
import magickHUDKit

/// magickHUD's side of the MacHUD contract: serves the control socket at
/// `~/Library/Application Support/MacHUD/sockets/magickhud.sock` through HUDKit's router.
/// See docs/CONTRACT.md for the verbs.
@MainActor
final class ControlHost: HUDPanelHost {
    static let panelID = "tools"
    static let actions = ["show", "hide", "toggle", "drop", "run", "jobs", "cancel", "presets", "files", "clear", "snapshot"]
    static let verbs = ["show", "hide", "toggle", "frame", "mode", "drop", "run", "jobs", "cancel", "presets", "files", "clear"]
    /// `action run` arguments that are not preset fields.
    static let runKeys: Set<String> = ["preset", "input", "inputs", "output", "wait", "show"]

    /// Used when running outside a bundle (e.g. `swift run`); mirrors Resources/machud.json.
    static let builtinManifest = HUDManifest(id: "xyz.machud.magickhud", name: "magickHUD", socket: "magickhud", panels: [
        HUDManifest.Panel(id: panelID, title: "magickHUD", symbol: "wand.and.stars",
                          defaultSize: HUDSize(PanelController.fullSize), compactSize: HUDSize(PanelController.compactSize),
                          capabilities: ["acceptsFileDrop"], verbs: verbs, settingsSchema: "settings.json", kind: .hover, order: 4),
    ])

    let manifest: HUDManifest
    let server: HUDSocketServer
    private(set) var router: HUDControlRouter!
    private let model: AppModel
    private let panel: PanelController
    private var lastPublished: String?
    private var routerWillPublish = false

    init(model: AppModel, panel: PanelController) {
        self.model = model
        self.panel = panel
        manifest = HUDManifest.main ?? Self.builtinManifest
        server = HUDSocketServer(path: HUDSocket.path(for: AppEnvironment.socketName(default: manifest.socket)),
                                 label: "magickhud.socket")
        router = HUDControlRouter(host: self, server: server, manifest: manifest)
    }

    func start() {
        router.install()
        if !server.start() { NSLog("magickHUD: control socket failed to start at %@", server.path) }
        panel.onStateChange = { [weak self] in self?.publishIfChanged() }
        model.onChange = { [weak self] in self?.publishIfChanged() }
    }

    func stop() { server.stop() }

    /// Pushes `state` to subscribers when anything they can see changed.
    func publishIfChanged() {
        let signature = panelStates.map { "\($0.visible)|\($0.mode)|\($0.badge ?? "")|\($0.status ?? "")" }.joined()
        guard signature != lastPublished else { return }
        lastPublished = signature
        if !routerWillPublish { router.publishState() }
    }

    private func routed(_ body: () throws -> Void) rethrows {
        routerWillPublish = true
        defer { routerWillPublish = false }
        try body()
        publishIfChanged()
    }

    // MARK: - HUDPanelHost

    var panelDescriptors: [HUDManifest.Panel] { manifest.panels }

    /// `badge`: running jobs, else dropped images (none when zero). `status`: the newest job's
    /// progress line, else the number of images.
    var badge: String? {
        if model.runningCount > 0 { return String(model.runningCount) }
        return model.files.isEmpty ? nil : String(model.files.count)
    }

    var status: String? {
        if let job = model.jobs.first(where: \.isActive) ?? model.jobs.first { return job.statusLine }
        return model.files.isEmpty ? nil : "\(model.files.count) image\(model.files.count == 1 ? "" : "s")"
    }

    var panelStates: [HUDPanelState] {
        [HUDPanelState(id: Self.panelID, visible: panel.isShown, mode: panel.mode, badge: badge, status: status)]
    }

    private func check(_ id: String) throws {
        guard id == Self.panelID else { throw HUDControlError.noSuchPanel(id) }
    }

    /// MacHUD shows a hover panel while the pointer is over its dock button, so a socket show
    /// never takes focus; the panel becomes key when clicked.
    func showPanel(_ id: String) throws { try check(id); routed { panel.show(takeFocus: false) } }
    func togglePanel(_ id: String) throws { try check(id); routed { panel.toggle(takeFocus: false) } }
    func hidePanel(_ id: String) throws { try check(id); routed { panel.hide() } }

    /// MacHUD's dock: `from=`/`anchor=` slide out of the button to the assigned frame,
    /// `reason=hover` is a 0.08 s show that never takes key, `click`/`summon` make the panel key.
    func showPanel(_ id: String, options: [String: String]) throws {
        try check(id); routed { panel.show(HUDPanelTransition(options)) }
    }

    /// `to=<edge>` slides back toward the dock in 0.1 s.
    func hidePanel(_ id: String, options: [String: String]) throws {
        try check(id); routed { panel.hide(HUDPanelTransition(options)) }
    }

    func togglePanel(_ id: String, options: [String: String]) throws {
        try check(id); routed { panel.toggle(HUDPanelTransition(options)) }
    }

    func setPanelFrame(_ id: String, frame: CGRect) throws {
        try check(id)
        guard frame.width >= 40, frame.height >= 40 else { throw HUDControlError.invalid("frame too small") }
        routed { panel.setFrame(frame) }
    }

    func setPanelMode(_ id: String, mode: HUDPanelMode) throws {
        try setPanelMode(id, mode: mode, options: HUDPanelModeOptions())
    }

    func setPanelMode(_ id: String, mode: HUDPanelMode, options: HUDPanelModeOptions) throws {
        try check(id)
        routed { panel.setMode(mode, options: options) }
    }

    // MARK: Settings

    func settings() -> [String: Any] { model.settings.json }

    func updateSettings(_ values: [String: String]) throws {
        do {
            try model.updateSettings(values)
        } catch let error as MagickSettings.SettingsError {
            throw HUDControlError.invalid(error.description)
        }
    }

    // MARK: Actions

    static func fileJSON(_ file: DroppedFile) -> [String: Any] {
        var d: [String: Any] = ["path": file.path]
        if let info = file.info { d.merge(info.json) { a, _ in a } }
        return d
    }

    static func presetJSON(_ preset: Preset) -> [String: Any] {
        ["id": preset.id, "title": preset.title, "summary": preset.summary, "combinesInputs": preset.combinesInputs,
         "fields": preset.fields.map { f -> [String: Any] in
             var d: [String: Any] = ["id": f.id, "label": f.label, "kind": f.kind.rawValue, "default": f.defaultValue]
             if !f.options.isEmpty { d["options"] = f.options.map(\.value) }
             if f.required { d["required"] = true }
             return d
         }]
    }

    /// `action run wait=1`'s reply: ok only when every file was written.
    static func finishedJSON(_ job: Job) -> [String: Any] {
        var d: [String: Any] = ["ok": job.state == .done, "job": job.json]
        if job.state != .done { d["error"] = job.items.compactMap(\.error).first ?? job.state.rawValue }
        return d
    }

    func performAction(_ name: String, args: [String: String], done: @escaping ([String: Any]) -> Void) {
        do {
            switch name {
            case "show", "hide", "toggle":
                routed {
                    switch name {
                    case "show": panel.show(takeFocus: false)
                    case "hide": panel.hide()
                    default: panel.toggle(takeFocus: false)
                    }
                }
                done(["ok": true, "visible": panel.isShown])
            case "drop":
                // HUDDrop: pipe-separated, percent-encoded; `file://` URLs and plain paths too.
                let paths = HUDDrop.urls(from: args).map(\.path)
                guard !paths.isEmpty else {
                    throw HUDControlError.invalid("paths= required: pipe-separated, percent-encoded paths")
                }
                if PresetField.bool(args["show"]) { panel.show(takeFocus: false) }
                model.drop(paths) { [weak self] added in
                    guard let self else { return }
                    let addedPaths = Set(added.map(\.path))
                    let skipped = paths.filter { p in
                        let std = (p as NSString).standardizingPath
                        return !addedPaths.contains(std) && !self.model.files.contains { $0.path == std }
                    }
                    self.publishIfChanged()
                    done(["ok": true, "added": added.map(Self.fileJSON), "skipped": skipped,
                          "count": self.model.files.count])
                }
            case "run":
                guard let presetID = args["preset"], !presetID.isEmpty else {
                    throw HUDControlError.invalid("preset= required (\(PresetCatalog.all.map(\.id).joined(separator: ", ")))")
                }
                guard let preset = PresetCatalog.preset(presetID) else {
                    throw HUDControlError.invalid("unknown preset \(presetID) (\(PresetCatalog.all.map(\.id).joined(separator: ", ")))")
                }
                var values: [String: String] = [:]
                for (key, value) in args where !Self.runKeys.contains(key) && key != "_" {
                    guard preset.field(key) != nil else {
                        throw HUDControlError.invalid("\(presetID) has no field \(key) (fields: \(preset.fields.map(\.id).joined(separator: ", ")))")
                    }
                    values[key] = value
                }
                let inputs = (args["input"] ?? args["inputs"]).map { HUDDrop.decode($0).map(\.path) }
                let wait = PresetField.bool(args["wait"])
                if PresetField.bool(args["show"]) { panel.show(takeFocus: false) }
                let finish: ((Job) -> Void)? = wait ? { finished in done(Self.finishedJSON(finished)) } : nil
                let job = try model.run(presetID: presetID, inputs: inputs, values: values,
                                        outputTemplate: args["output"], onFinish: finish)
                if !wait { done(["ok": true, "job": job.json]) }
            case "jobs":
                if let id = args["id"] {
                    guard let job = model.jobs.first(where: { $0.id == id }) else { throw HUDControlError.invalid("no job \(id)") }
                    done(["ok": true, "job": job.json])
                } else {
                    done(["ok": true, "running": model.runningCount, "jobs": model.jobs.map(\.json)])
                }
            case "cancel":
                let ids = args["id"].map { [$0] } ?? model.jobs.filter(\.isActive).map(\.id)
                ids.forEach(model.cancel)
                done(["ok": true, "cancelled": ids])
            case "presets":
                let presets = args["query"].map(PresetCatalog.search) ?? PresetCatalog.all
                done(["ok": true, "presets": presets.map(Self.presetJSON)])
            case "files":
                done(["ok": true, "count": model.files.count, "files": model.files.map(Self.fileJSON)])
            case "clear":
                model.clearFiles()
                done(["ok": true, "count": 0])
            case "snapshot":
                guard let path = args["path"], !path.isEmpty else { throw HUDControlError.invalid("path= required") }
                if let preset = args["preset"] {
                    guard PresetCatalog.preset(preset) != nil else { throw HUDControlError.invalid("unknown preset \(preset)") }
                    model.presetID = preset
                }
                // Let SwiftUI lay out any change first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [panel] in
                    panel.writeSnapshot(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
                    done(["ok": true, "path": path])
                }
            default:
                throw HUDControlError.invalid("unknown action \(name) (\(Self.actions.joined(separator: ", ")))")
            }
        } catch let error as BuildError {
            done(["ok": false, "error": error.description])
        } catch {
            done(["ok": false, "error": "\(error)"])
        }
    }

    func quit() { NSApp.terminate(nil) }
}
