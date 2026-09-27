import AppKit
import Carbon
import HUDKit
import magickHUDKit
import SwiftUI

/// Owns the panel window: visibility, the full / compact / parked modes, frames (including
/// frames MacHUD assigns over the socket), keyboard shortcuts and snapshots. The panel is
/// HUDKit's non-activating recipe, keyable so the search and form fields take typing without
/// activating the app.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let fullSize = CGSize(width: 720, height: 560)
    static let compactSize = CGSize(width: 44, height: 44)
    static let fullStyle = HUDGlassView.Style(cornerRadius: 16, borderWidth: 0.5, borderAlpha: 0.22, gloss: false)
    static let compactStyle = HUDGlassView.Style(cornerRadius: 12, borderWidth: 0.5, borderAlpha: 0.2, gloss: true)
    static let minFullSize = NSSize(width: 560, height: 400)

    let model: AppModel
    let panel: HUDPanelWindow
    private let glass: HUDGlassView
    private var host: NSHostingView<RootView>!
    private var keyMonitor: Any?

    /// The mode shown (or returned to when unparking).
    private(set) var mode: HUDPanelMode = .full
    private var modeBeforeParking: HUDPanelMode = .full
    private var restFrame: CGRect?
    /// The edge and peek to park at (MacHUD's, once it has named them).
    private(set) var parking = ParkingSpot(peek: 14)
    /// Whether the panel is meant to be on screen (tracked apart from `isVisible`, which is
    /// still true during the fade-out).
    private(set) var isShown = false
    private var isAdjustingFrame = false
    /// The frame MacHUD assigned with `panel frame`; dock shows rest there. Cleared when the
    /// user moves or resizes the panel, or the mode changes.
    private(set) var assignedFrame: CGRect?
    /// Bumped by every dock slide; the slide whose token is current owns the frame, so
    /// `windowDidMove` does not save the frames it passes through.
    private var slideToken = 0
    private var isSliding = false
    /// Where the panel rests during a slide (the live frame is partway there).
    private var slideRest: CGRect?

    /// `reason=hover`: near-instant, so moving between dock buttons cross-fades.
    static let hoverShowDuration: TimeInterval = 0.08
    /// `hide to=<edge>`: MacHUD hides when the pointer leaves, so it goes almost at once.
    static let slideHideDuration: TimeInterval = 0.1
    /// Set while a "brief" show is pending its automatic hide.
    private var briefHide: DispatchWorkItem?

    /// Called whenever visibility, mode or frame changes (for `state` events).
    var onStateChange: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        panel = HUDPanelWindow(contentRect: CGRect(origin: .zero, size: Self.fullSize),
                             styleMask: HUDPanelWindow.recipeStyleMask.union(.resizable), backing: .buffered, defer: false)
        glass = HUDGlassView(style: Self.fullStyle)
        super.init()
        host = NSHostingView(rootView: RootView(model: model,
                                                expand: { [weak self] in self?.setMode(.full, takeFocus: true) },
                                                dismiss: { [weak self] in self?.hide() },
                                                compact: { [weak self] in self?.setMode(.compact) },
                                                openFiles: { [weak self] in self?.openFiles() }))

        panel.keyable = true
        panel.applyHUDRecipe()
        panel.title = "magickHUD"
        panel.identifier = NSUserInterfaceItemIdentifier("xyz.machud.magickhud.tools")
        panel.becomesKeyOnlyIfNeeded = false
        panel.minSize = Self.minFullSize
        panel.delegate = self

        host.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass

        if let saved = Self.savedFrame(Self.fullFrameKey) {
            panel.setFrame(saved, display: false)
        } else {
            centerOnMouseScreen()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    // MARK: - Keys

    /// Shortcuts for the panel. A non-activating panel of a menu-bar app has no main menu to
    /// route key equivalents, so the standard editing commands are dispatched here too.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if Int(event.keyCode) == kVK_Escape, flags.isEmpty {
            if !model.search.isEmpty, !model.isCompact { model.search = ""; return true }
            hide()
            return true
        }
        guard flags.contains(.command) else { return false }
        let responder = panel.firstResponder
        func send(_ selector: Selector) -> Bool {
            responder?.tryToPerform(selector, with: nil)
            return true
        }
        switch (key, flags) {
        case ("\r", [.command]):
            if case .success = model.plan { _ = try? model.run() }
            return true
        case ("c", [.command, .shift]): model.copyCommand(); return true
        case ("f", [.command]): model.focusSearch(); return true
        case ("o", [.command]): openFiles(); return true
        case ("w", [.command]): hide(); return true
        case ("x", [.command]): return send(#selector(NSText.cut(_:)))
        case ("c", [.command]): return send(#selector(NSText.copy(_:)))
        case ("v", [.command]): return send(#selector(NSText.paste(_:)))
        case ("a", [.command]): return send(#selector(NSText.selectAll(_:)))
        case ("z", [.command]): responder?.undoManager?.undo(); return true
        case ("z", [.command, .shift]): responder?.undoManager?.redo(); return true
        default:
            return false
        }
    }

    /// Cmd-O: pick images with an open panel.
    func openFiles() {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = true
        open.canChooseDirectories = true
        open.allowedContentTypes = [.image, .pdf]
        open.level = .modalPanel
        if open.runModal() == .OK { model.drop(open.urls.map(\.path)) }
    }

    var isVisible: Bool { isShown }

    // MARK: - Visibility

    /// Shows the panel at its last frame and mode, with the dropped files, form and jobs as they
    /// were. `takeFocus` makes it key at once, for the user's own summons (hotkey, menu bar);
    /// MacHUD's socket shows (hover) pass false so the pointer passing over the dock never
    /// takes typing away from the app in front: the panel becomes key when clicked. Either
    /// way the app is never activated (the panel is non-activating).
    func show(takeFocus: Bool = true, duration: TimeInterval = HUDAnimation.revealDuration) {
        cancelBriefHide()
        if mode == .parked { return unpark(takeFocus: takeFocus) }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { centerOnMouseScreen() }
        let wasShown = isShown
        isShown = true
        // A fade replaces a dock slide in flight: put the panel back where that slide rests.
        if isSliding, let slideRest { setFrameQuietly(slideRest) }
        endSlide()
        let front = { [panel] in takeFocus ? panel.makeKeyAndOrderFront(nil) : panel.orderFrontRegardless() }
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 0
            front()
            HUDAnimation.fadeIn(panel, duration: duration)
        } else {
            front()
        }
        if !wasShown { onStateChange?() }
    }

    /// A show from MacHUD's dock (`panel show from= anchor= reason=`). With `from=` the panel
    /// slides out of that edge to the frame MacHUD assigned (`panel frame`), else next to the
    /// anchor button, else where it is. `reason=hover` takes 0.08 s and never takes key; only
    /// `click`/`summon` make the (non-activating) panel key. Without `from=` this is `show`.
    func show(_ t: HUDPanelTransition) {
        cancelBriefHide()
        let takeFocus = t.reason == .click || t.reason == .summon
        guard let from = t.from, mode != .parked else {
            return show(takeFocus: takeFocus,
                        duration: t.reason == .hover ? Self.hoverShowDuration : HUDAnimation.revealDuration)
        }
        let current = isSliding ? slideRest ?? panel.frame : panel.frame
        let rest = Self.restFrame(assigned: assignedFrame, transition: t, current: current)
        let wasShown = isShown
        isShown = true
        let token = beginSlide(resting: rest)
        HUDAnimation.slide(in: panel, from: from, to: rest,
                           duration: t.reason == .hover ? Self.hoverShowDuration : HUDAnimation.revealDuration) { [weak self] in
            self?.endSlide(token)
        }
        if takeFocus { panel.makeKey() }
        if !wasShown { onStateChange?() }
    }

    /// Where a dock show rests: the `panel frame` MacHUD assigned, else next to the anchor
    /// (`HUDPanelTransition.panelFrame`), else the current frame.
    static func restFrame(assigned: CGRect?, transition t: HUDPanelTransition, current: CGRect) -> CGRect {
        if let assigned { return assigned }
        return t.panelFrame(size: current.size) ?? current
    }

    /// A hide from MacHUD's dock: `to=<edge>` slides back toward it in 0.1 s; otherwise `hide`.
    func hide(_ t: HUDPanelTransition) {
        cancelBriefHide()
        guard let to = t.to, mode != .parked else { return hide() }
        guard isShown else { return }
        isShown = false
        let token = beginSlide(resting: isSliding ? slideRest ?? panel.frame : panel.frame)
        HUDAnimation.slideOut(panel, toward: to, duration: Self.slideHideDuration) { [weak self] in
            self?.endSlide(token)
        }
        onStateChange?()
    }

    /// `panel toggle` with dock options; hiding slides toward `to=`, else back into `from=`.
    func toggle(_ t: HUDPanelTransition) {
        if mode == .parked { return unpark(takeFocus: t.reason == .click || t.reason == .summon) }
        guard isShown else { return show(t) }
        var back = t
        if back.to == nil { back.to = t.from }
        hide(back)
    }

    private func beginSlide(resting rest: CGRect) -> Int {
        slideToken += 1
        isSliding = true
        slideRest = rest
        return slideToken
    }

    /// Ends the slide `token` (a superseded slide's completion does nothing), or any slide.
    private func endSlide(_ token: Int? = nil) {
        if let token, token != slideToken { return }
        if token == nil { slideToken += 1 }
        isSliding = false
        slideRest = nil
    }

    /// Shows the panel without taking focus and hides it again after `duration`, unless the
    /// user moves into it or it becomes key meanwhile. A panel already on screen is left alone.
    func showBriefly(duration: TimeInterval = 1.8) {
        guard !isShown || briefHide != nil else { return }
        if mode == .parked { return unpark() }
        cancelBriefHide()
        if !isShown {
            isShown = true
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { centerOnMouseScreen() }
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            HUDAnimation.animate(panel, alpha: 1, duration: HUDAnimation.revealDuration, timing: HUDAnimation.revealTiming)
            onStateChange?()
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.briefHide = nil
            if self.panel.isKeyWindow || self.panel.frame.contains(NSEvent.mouseLocation) { return }
            self.hide()
        }
        briefHide = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func cancelBriefHide() {
        briefHide?.cancel()
        briefHide = nil
    }

    func hide() {
        cancelBriefHide()
        guard isShown else { return }
        isShown = false
        endSlide()
        if mode == .parked, let restFrame {
            mode = modeBeforeParking
            setFrameQuietly(restFrame)
            self.restFrame = nil
        }
        HUDAnimation.fadeOut(panel) { [weak self] in
            // A show() during the fade wins.
            if let self, self.isShown { self.panel.alphaValue = 1; self.panel.orderFront(nil) }
        }
        onStateChange?()
    }

    func toggle(takeFocus: Bool = true) {
        if mode == .parked { return unpark(takeFocus: takeFocus) }
        if takeFocus {
            isShown && panel.isKeyWindow ? hide() : show()
        } else {
            isShown ? hide() : show(takeFocus: false)
        }
    }

    // MARK: - Modes

    /// `options` carry the edge/peek MacHUD parks at; they only matter for `.parked`.
    func setMode(_ newMode: HUDPanelMode, options: HUDPanelModeOptions = HUDPanelModeOptions(),
                 takeFocus: Bool = false) {
        switch newMode {
        case .parked:
            park(options)
        case .full, .compact:
            if mode == .parked { unpark(to: newMode, takeFocus: takeFocus) } else { apply(newMode) }
            if !isShown { show(takeFocus: takeFocus) } else if takeFocus { panel.makeKey() }
        }
        onStateChange?()
    }

    private func apply(_ newMode: HUDPanelMode) {
        guard newMode != mode else { return }
        saveCurrentFrame()
        assignedFrame = nil
        mode = newMode
        model.isCompact = newMode == .compact
        glass.style = newMode == .compact ? Self.compactStyle : Self.fullStyle
        if newMode == .compact {
            panel.styleMask.remove(.resizable)
            panel.minSize = Self.compactSize
            setFrameQuietly(Self.savedFrame(Self.compactFrameKey) ?? defaultCompactFrame(), animate: isShown)
        } else {
            panel.styleMask.insert(.resizable)
            panel.minSize = Self.minFullSize
            setFrameQuietly(Self.savedFrame(Self.fullFrameKey) ?? defaultFullFrame(), animate: isShown)
        }
        panel.invalidateShadow()
    }

    private func park(_ options: HUDPanelModeOptions) {
        let moved = parking.update(with: options)
        if mode == .parked {
            // Already parked: move to the newly requested edge or peek.
            if moved, let restFrame { setFrameQuietly(parking.offScreenFrame(for: restFrame)) }
            return
        }
        if !isShown { show(takeFocus: false) }
        modeBeforeParking = mode
        restFrame = panel.frame
        mode = .parked
        let edge = parking.edge(for: panel.frame, in: HUDParking.screenFrame(for: panel.frame))
        isAdjustingFrame = true
        HUDParking.slideOut(panel, edge: edge, peek: parking.peek) { [weak self] in self?.isAdjustingFrame = false }
    }

    private func unpark(to target: HUDPanelMode? = nil, takeFocus: Bool = true) {
        guard mode == .parked else { return }
        let rest = restFrame ?? panel.frame
        mode = modeBeforeParking
        restFrame = nil
        isShown = true
        isAdjustingFrame = true
        HUDParking.slideIn(panel, to: rest) { [weak self] in
            guard let self else { return }
            self.isAdjustingFrame = false
            if let target, target != self.mode { self.apply(target) }
            if takeFocus { self.panel.makeKey() }
            self.onStateChange?()
        }
    }

    /// Cooperative placement from MacHUD (`panel frame`), kept as the frame for the current mode.
    func setFrame(_ frame: CGRect) {
        assignedFrame = frame
        if mode == .parked {
            restFrame = frame
            setFrameQuietly(parking.offScreenFrame(for: frame))
            return
        }
        setFrameQuietly(frame)
        saveCurrentFrame()
        onStateChange?()
    }

    private func setFrameQuietly(_ frame: CGRect, animate: Bool = false) {
        isAdjustingFrame = true
        panel.setFrame(frame, display: true, animate: animate)
        isAdjustingFrame = false
    }

    // MARK: - Frames

    private static let fullFrameKey = "MagickFullFrame"
    private static let compactFrameKey = "MagickCompactFrame"

    private static func savedFrame(_ key: String) -> CGRect? {
        guard let string = AppEnvironment.defaults.string(forKey: key) else { return nil }
        let rect = NSRectFromString(string)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    private func saveCurrentFrame() {
        switch mode {
        case .full: AppEnvironment.defaults.set(NSStringFromRect(panel.frame), forKey: Self.fullFrameKey)
        case .compact: AppEnvironment.defaults.set(NSStringFromRect(panel.frame), forKey: Self.compactFrameKey)
        case .parked: break
        }
    }

    private func defaultFullFrame() -> CGRect {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(origin: .zero, size: Self.fullSize)
        return CGRect(x: visible.midX - Self.fullSize.width / 2, y: visible.midY - Self.fullSize.height / 2,
                      width: Self.fullSize.width, height: Self.fullSize.height)
    }

    /// The tile starts at the top-right corner of where the full panel was.
    private func defaultCompactFrame() -> CGRect {
        let full = panel.frame
        let frame = CGRect(x: full.maxX - Self.compactSize.width, y: full.maxY - Self.compactSize.height,
                           width: Self.compactSize.width, height: Self.compactSize.height)
        return HUDParking.restFrame(for: frame, in: HUDParking.screenFrame(for: full))
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame, !isSliding, !panel.inLiveResize else { return }
        userPlaced()
    }

    func windowDidEndLiveResize(_ notification: Notification) { userPlaced() }

    /// The user dragged or resized the panel: that frame wins over MacHUD's until it assigns another.
    private func userPlaced() {
        assignedFrame = nil
        saveCurrentFrame()
    }

    private func centerOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }

    // MARK: - Snapshot

    /// Writes a PNG of the panel. The glass backdrop blurs what is behind the window, which a
    /// view cache cannot capture, so the content is composited on a dark stand-in with the
    /// panel's corners and hairline border.
    func writeSnapshot(to url: URL) {
        let view: NSView = host
        let scale = panel.backingScaleFactor
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let radius = (mode == .compact ? Self.compactStyle : Self.fullStyle).cornerRadius
        let rect = CGRect(origin: .zero, size: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()
        NSGraphicsContext.restoreGraphicsState()
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            NSLog("magickHUD: snapshot failed: %@", error.localizedDescription)
        }
    }
}
