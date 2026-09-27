import Foundation
import HUDKit
import XCTest

/// The shipped machud.json, settings.json and Info.plist are what MacHUD reads without launching
/// magickHUD; keep them valid.
final class ManifestTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/magickHUD/Resources")
    }

    func testManifestDecodes() throws {
        let manifest = try HUDManifest.decode(Data(contentsOf: resources.appendingPathComponent(HUDManifest.fileName)))
        XCTAssertEqual(manifest.id, "xyz.machud.magickhud")
        XCTAssertEqual(manifest.name, "magickHUD")
        XCTAssertEqual(manifest.socket, "magickhud")
        let panel = try XCTUnwrap(manifest.panel(id: "tools"))
        XCTAssertEqual(panel.kind, .hover)
        XCTAssertEqual(panel.capabilities, ["acceptsFileDrop"])
        XCTAssertEqual(panel.order, 4, "MacHUD's dock: Scratch 1, Stash 2, ffmpegHUD 3, then magickHUD")
        XCTAssertEqual(panel.compactSize, HUDSize(width: 44, height: 44))
        for verb in ["show", "hide", "toggle", "drop", "run", "jobs"] {
            XCTAssertTrue(panel.verbs.contains(verb), verb)
        }
        let schema = try XCTUnwrap(panel.settingsSchema)
        let decoded = try HUDSettingsSchema.decode(Data(contentsOf: resources.appendingPathComponent(schema)))
        XCTAssertEqual(Set(decoded.settings.map(\.key)),
                       ["output.policy", "output.subfolder", "output.folder", "output.suffix", "quality.default", "magick.path"])
    }

    func testInfoPlist() throws {
        let data = try Data(contentsOf: resources.appendingPathComponent("Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "xyz.machud.magickhud")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "magickHUD")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertNotNil(plist["NSHumanReadableCopyright"])
    }
}
