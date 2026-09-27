@testable import magickHUDKit
import XCTest

final class SettingsAndIdentifyTests: XCTestCase {
    func testIdentifyParsesTheFirstFrameAndCountsFrames() throws {
        let info = try XCTUnwrap(Identify.parse("PNG|64|48\n", bytes: 2048))
        XCTAssertEqual(info, ImageInfo(format: "PNG", width: 64, height: 48, frames: 1, bytes: 2048))
        XCTAssertEqual(info.dimensions, "64×48")
        let gif = try XCTUnwrap(Identify.parse("GIF|10|20\nGIF|10|20\nGIF|8|8\n"))
        XCTAssertEqual(gif.frames, 3)
        XCTAssertEqual(gif.width, 10)
        XCTAssertNil(Identify.parse(""))
        XCTAssertNil(Identify.parse("identify: no decode delegate for this image format"))
        XCTAssertNil(Identify.parse("PNG|x|48"))
        XCTAssertEqual(Identify.argv("/a b.png"), ["magick", "identify", "-ping", "-format", "%m|%w|%h\\n", "/a b.png"])
    }

    func testSettingsApplyValidatesEverything() throws {
        let s = MagickSettings()
        let changed = try s.applying(["output.policy": "subfolder", "quality.default": "70", "output.suffix": "-{preset}"])
        XCTAssertEqual(changed.outputPolicy, .subfolder)
        XCTAssertEqual(changed.defaultQuality, 70)
        XCTAssertEqual(changed.presetDefaults["quality"], "70")
        XCTAssertEqual(changed.naming.proposed(input: "/p/a.png", ext: "png", preset: "gray"), "/p/magickHUD/a-gray.png")
        XCTAssertThrowsError(try s.applying(["quality.default": "0"]))
        XCTAssertThrowsError(try s.applying(["output.policy": "desktop"]))
        XCTAssertThrowsError(try s.applying(["output.subfolder": "a/b"]))
        XCTAssertThrowsError(try s.applying(["output.suffix": "/x"]))
        XCTAssertThrowsError(try s.applying(["nope": "1"]))
        XCTAssertEqual(Set(s.json.keys), Set(MagickSettings.keys))
    }

    func testSettingsRoundTripAndTolerateMissingKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("magickhud-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("preferences.json")
        var s = MagickSettings()
        s.suffix = "_x"
        try s.save(to: url)
        XCTAssertEqual(MagickSettings.load(from: url), s)
        try Data(#"{"quality.default": 60}"#.utf8).write(to: url)
        XCTAssertEqual(MagickSettings.load(from: url).defaultQuality, 60)
        XCTAssertEqual(MagickSettings.load(from: url).suffix, "_{preset}")
    }

    func testOneUndecodableValueKeepsTheOtherSavedSettings() throws {
        let json = #"{"quality.default": "high", "output.suffix": "_y", "output.policy": "nonsense"}"#
        let s = try JSONDecoder().decode(MagickSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.defaultQuality, MagickSettings().defaultQuality)
        XCTAssertEqual(s.outputPolicy, MagickSettings().outputPolicy)
        XCTAssertEqual(s.suffix, "_y")
    }
}
