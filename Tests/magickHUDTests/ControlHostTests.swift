import AppKit
import HUDKit
@testable import magickHUD
import magickHUDKit
import XCTest

/// The socket verbs through HUDKit's router, on PNGs drawn with CoreGraphics in a temp folder.
@MainActor
final class ControlHostTests: XCTestCase {
    private var dir: URL!
    private var model: AppModel!
    private var control: ControlHost!

    private var panel: PanelController!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("magickhud-host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        model = AppModel(settingsURL: dir.appendingPathComponent("preferences.json"))
        panel = PanelController(model: model)
        control = ControlHost(model: model, panel: panel)
    }

    override func tearDown() async throws {
        panel.panel.orderOut(nil)
        panel = nil
        control = nil
        model = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// A solid PNG, written with ImageIO (no ImageMagick needed).
    private func png(_ name: String, width: Int = 64, height: Int = 48) throws -> String {
        let url = dir.appendingPathComponent(name)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url.path
    }

    private func send(_ verb: String, _ args: [String: String], timeout: TimeInterval = 20) -> [String: Any] {
        let replied = expectation(description: "\(verb) \(args)")
        var response: [String: Any] = [:]
        control.router.handle(verb, args: args) { response = $0; replied.fulfill() }
        wait(for: [replied], timeout: timeout)
        return response
    }

    func testDropAcceptsFileURLsAndPlainPaths() throws {
        let a = try png("plain one.png")
        let b = try png("url two.png")
        let response = send("action", ["_": "drop", "paths": a + "|" + URL(fileURLWithPath: b).absoluteString])
        let added = try XCTUnwrap(response["added"] as? [[String: Any]], "\(response)")
        XCTAssertEqual(added.compactMap { $0["path"] as? String }, [a, b])
    }

    func testDockTransitionsThroughRouter() throws {
        func panelCmd(_ args: [String: String]) -> [String: Any] { send("panel", ["id": "tools"].merging(args) { $1 }) }
        // Inside the main screen's visible area, so AppKit does not push the window on-screen on a
        // small display (the CI runner's).
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let assigned = CGRect(x: (visible.minX + 40).rounded(), y: (visible.minY + 40).rounded(), width: 720, height: 560)
        XCTAssertEqual(panelCmd(["frame": "1", "x": "\(Int(assigned.minX))", "y": "\(Int(assigned.minY))", "w": "720", "h": "560"])["ok"] as? Bool, true)

        // Hover show: slides out of the bottom dock to the assigned frame, never takes key.
        let shown = panelCmd(["show": "1", "from": "bottom", "anchor": "100,0,44,44", "reason": "hover"])
        XCTAssertEqual(shown["visible"] as? Bool, true, "\(shown)")
        spin(until: panel.panel.frame == assigned)
        XCTAssertTrue(panel.panel.isVisible)
        XCTAssertFalse(panel.panel.isKeyWindow, "hover must not take key")
        XCTAssertEqual(panel.panel.frame, assigned)

        // Pointer leaves and comes straight back: the show wins over the hide in flight.
        XCTAssertEqual(panelCmd(["hide": "1", "to": "bottom"])["visible"] as? Bool, false)
        XCTAssertEqual(panelCmd(["show": "1", "from": "bottom", "anchor": "100,0,44,44", "reason": "hover"])["visible"] as? Bool, true)
        spin(until: panel.panel.frame == assigned && panel.panel.alphaValue == 1)
        XCTAssertTrue(panel.panel.isVisible, "the stale hide must not order the panel out")
        XCTAssertEqual(panel.panel.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(panel.panel.frame, assigned)

        // A hide on its own slides out, orders out and restores the rest frame.
        XCTAssertEqual(panelCmd(["hide": "1", "to": "bottom"])["visible"] as? Bool, false)
        spin(until: !panel.panel.isVisible && panel.panel.frame == assigned)
        XCTAssertFalse(panel.panel.isVisible)
        XCTAssertEqual(panel.panel.frame, assigned)

        // Without an assigned frame the panel rests next to the anchor, above a bottom dock.
        panel.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
        XCTAssertNil(panel.assignedFrame, "a user resize drops MacHUD's frame")
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let button = CGRect(x: screen.midX - 22, y: screen.minY, width: 44, height: 44)
        _ = panelCmd(["show": "1", "from": "bottom", "anchor": HUDPanelTransition.formatAnchor(button), "reason": "click"])
        spin(until: abs(panel.panel.frame.midX - button.midX) < 0.5 && panel.panel.frame.minY >= button.maxY)
        XCTAssertEqual(panel.panel.frame.size, assigned.size)
        XCTAssertEqual(panel.panel.frame.midX, button.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(panel.panel.frame.minY, button.maxY)

        XCTAssertEqual(panelCmd(["show": "1", "from": "middle"])["ok"] as? Bool, false)
        XCTAssertEqual(PanelController.hoverShowDuration, 0.08)
        XCTAssertEqual(PanelController.slideHideDuration, 0.1)
    }

    /// Spins the main run loop until `condition` holds or `timeout` passes: the motions are
    /// run-loop animations, and the CI runner is slow to advance them.
    private func spin(until condition: @autoclosure () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testDropDecodesPathsAndIdentifies() throws {
        let a = try png("a b|c.png")
        let b = try png("second%.png", width: 20, height: 10)
        let response = send("action", ["_": "drop", "paths": HUDDrop.encode([a, b, "/nope/missing.png", dir.appendingPathComponent("x.txt").path].map(URL.init(fileURLWithPath:)))])
        XCTAssertEqual(response["ok"] as? Bool, true)
        let added = try XCTUnwrap(response["added"] as? [[String: Any]])
        XCTAssertEqual(added.compactMap { $0["path"] as? String }, [a, b])
        XCTAssertEqual(added.first?["width"] as? Int, 64)
        XCTAssertEqual(added.last?["height"] as? Int, 10)
        XCTAssertEqual((response["skipped"] as? [String])?.count, 2)
        XCTAssertEqual(model.files.count, 2)

        // Dropping the same file again does not duplicate it; the badge counts images.
        _ = send("action", ["name": "drop", "paths": HUDDrop.encode([a].map(URL.init(fileURLWithPath:)))])
        XCTAssertEqual(model.files.count, 2)
        XCTAssertEqual(control.panelStates.first?.badge, "2")
        XCTAssertEqual(control.panelStates.first?.status, "2 images")

        XCTAssertEqual(send("action", ["_": "clear"])["count"] as? Int, 0)
        XCTAssertNil(control.panelStates.first?.badge)
        XCTAssertEqual(send("action", ["_": "drop"])["ok"] as? Bool, false, "paths= is required")
    }

    func testRunValidatesPresetAndFields() throws {
        let a = try png("a.png")
        XCTAssertEqual(send("action", ["_": "run"])["ok"] as? Bool, false)
        XCTAssertEqual(send("action", ["_": "run", "preset": "nope", "input": a])["ok"] as? Bool, false)
        let bad = send("action", ["_": "run", "preset": "resize", "input": a, "colour": "red"])
        XCTAssertEqual(bad["ok"] as? Bool, false)
        XCTAssertTrue((bad["error"] as? String ?? "").contains("no field colour"))
        XCTAssertEqual(send("action", ["_": "run", "preset": "resize"])["error"] as? String, "drop an image first")
        XCTAssertEqual(send("action", ["_": "run", "preset": "resize", "input": "/nope.png"])["ok"] as? Bool, false)
    }

    func testRunResizeWritesANewFileAndListsTheJob() throws {
        guard model.magick != nil else { throw XCTSkip("magick is not installed") }
        let a = try png("photo.png")
        let response = send("action", ["_": "run", "preset": "resize", "input": HUDDrop.encode([a].map(URL.init(fileURLWithPath:))), "width": "32", "wait": "1"])
        XCTAssertEqual(response["ok"] as? Bool, true, "\(response)")
        let job = try XCTUnwrap(response["job"] as? [String: Any])
        let output = try XCTUnwrap((job["outputs"] as? [String])?.first)
        XCTAssertEqual(output, dir.appendingPathComponent("photo_resized.png").path)
        XCTAssertEqual(Identify.info(output)?.dimensions, "32×24")

        // Again: never overwrites.
        let again = send("action", ["_": "run", "preset": "resize", "input": a, "width": "32", "wait": "1"])
        XCTAssertEqual(((again["job"] as? [String: Any])?["outputs"] as? [String])?.first,
                       dir.appendingPathComponent("photo_resized-2.png").path)

        let jobs = send("action", ["_": "jobs"])
        XCTAssertEqual((jobs["jobs"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((jobs["jobs"] as? [[String: Any]])?.first?["state"] as? String, "done")
        XCTAssertEqual(control.panelStates.first?.status, "Resize: 1 done")
    }

    func testPresetsAndSettings() throws {
        let presets = send("action", ["_": "presets", "query": "gps"])
        XCTAssertEqual((presets["presets"] as? [[String: Any]])?.map { $0["id"] as? String }, ["strip"])
        XCTAssertEqual(send("settings", ["action": "set", "quality.default": "70"])["ok"] as? Bool, true)
        XCTAssertEqual(model.settings.defaultQuality, 70)
        XCTAssertEqual(MagickSettings.load(from: dir.appendingPathComponent("preferences.json")).defaultQuality, 70)
        XCTAssertEqual(send("settings", ["action": "set", "quality.default": "700"])["ok"] as? Bool, false)
    }

    func testBuiltinManifestMirrorsTheBundledOne() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/magickHUD/Resources/machud.json")
        XCTAssertEqual(ControlHost.builtinManifest, try HUDManifest.decode(Data(contentsOf: url)))
    }
}
