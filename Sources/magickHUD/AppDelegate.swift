import AppKit
import HUDKit
import magickHUDKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private var control: ControlHost!
    static let toggleHotKey = HUDHotKey(key: "i", modifiers: ["control", "option"])

    func applicationDidFinishLaunching(_ notification: Notification) {
        HUDEditMenu.install(appName: "magickHUD")
        model = AppModel(settingsURL: AppEnvironment.settingsURL)
        panel = PanelController(model: model)
        control = ControlHost(model: model, panel: panel)
        control.start()
        setupStatusItem()
        // While MacHUD runs, its menu hosts this one and the icon hides (HUDKit menu bar consolidation).
        control.router.menuProvider = { [weak self] in self?.statusItem?.menu }
        // menuBar.consumed is kept in <home>/menubar.json, so MAGICKHUD_HOME isolates it too.
        HUDStatusItemPolicy.attach(statusItem, appID: control.manifest.id, store: .home(AppEnvironment.baseDirectory))
        if AppEnvironment.hotKeysEnabled,
           HUDHotKeyCenter.shared.register(Self.toggleHotKey, onPress: { [weak self] in self?.panel.toggle() }) == nil {
            model.show("⌃⌥I is taken by another app; use the menu bar icon", error: true)
        }

        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        // `--preset <id>`: start on that preset. `--drop <paths>` (pipe-separated, percent-encoded):
        // start with those files. `--run`: run the preset on them once they are identified.
        // All three are for --snapshot.
        if let id = value("--preset"), PresetCatalog.preset(id) != nil { model.presetID = id }
        var runFinished = !args.contains("--run")
        if let payload = value("--drop") {
            model.drop(HUDDrop.decode(payload).map(\.path)) { [weak self] _ in
                guard let self, args.contains("--run") else { return }
                if (try? self.model.run(onFinish: { _ in runFinished = true })) == nil { runFinished = true }
            }
        }
        // Never take the keyboard at launch: the panel becomes key when clicked, or when summoned
        // with the hotkey or the menu bar item.
        panel.show(takeFocus: false)

        // `--snapshot <path.png>`: write a PNG of the panel once it settles (after the run, with
        // --run), for docs and for checking the UI without Screen Recording permission.
        // `--snapshot-mode compact` pictures the tile.
        if let path = value("--snapshot") {
            if value("--snapshot-mode") == "compact" { panel.setMode(.compact) }
            var waited = 0.0
            func attempt() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    waited += 0.5
                    guard let self else { return }
                    if (!runFinished || waited < 2) && waited < 20 { return attempt() }
                    // The after thumbnail arrives a moment after the job.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.panel.writeSnapshot(to: URL(fileURLWithPath: path))
                    }
                }
            }
            attempt()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.jobs.filter(\.isActive).forEach { model.cancel($0.id) }
        control.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return true
    }

    // MARK: - Status item

    private enum Tag: Int { case toggle = 1, compact }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = HUDStatusIcon.image(fallbackSymbol: "wand.and.stars", accessibilityDescription: "magickHUD")

        let menu = NSMenu()
        menu.delegate = self
        let toggle = NSMenuItem(title: "Show magickHUD", action: #selector(togglePanel), keyEquivalent: "i")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.tag = Tag.toggle.rawValue
        menu.addItem(toggle)
        menu.addItem(NSMenuItem(title: "Add Images…", action: #selector(addImages), keyEquivalent: ""))
        let compact = NSMenuItem(title: "Compact Tile", action: #selector(toggleCompact), keyEquivalent: "")
        compact.tag = Tag.compact.rawValue
        menu.addItem(compact)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit magickHUD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) && item.target == nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch Tag(rawValue: item.tag) {
            case .toggle: item.title = panel.isVisible ? "Hide magickHUD" : "Show magickHUD"
            case .compact: item.state = panel.mode == .compact ? .on : .off
            case nil: break
            }
        }
    }

    @objc private func togglePanel() { panel.toggle() }
    @objc private func addImages() {
        if panel.mode != .full { panel.setMode(.full, takeFocus: true) }
        panel.show()
        panel.openFiles()
    }
    @objc private func toggleCompact() { panel.setMode(panel.mode == .compact ? .full : .compact, takeFocus: true) }
}
