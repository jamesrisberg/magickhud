@testable import magickHUDKit
import XCTest

final class NamingTests: XCTestCase {
    func testTokens() {
        let t = Tokens(input: "/pics/holiday.photo.JPG", output: "/out/x.jpg", ext: "jpg", preset: "resized")
        XCTAssertEqual(t.dir, "/pics")
        XCTAssertEqual(t.name, "holiday.photo")
        XCTAssertEqual(t.expand("{dir}/{name}-{preset}.{ext} {input} {output}"),
                       "/pics/holiday.photo-resized.jpg /pics/holiday.photo.JPG /out/x.jpg")
    }

    func testPolicies() {
        var naming = OutputNaming()
        XCTAssertEqual(naming.proposed(input: "/p/a.png", ext: "png", preset: "gray"), "/p/a_gray.png")
        naming.policy = .subfolder
        XCTAssertEqual(naming.proposed(input: "/p/a.png", ext: "webp", preset: "gray"), "/p/magickHUD/a_gray.webp")
        naming.policy = .folder
        naming.folder = "/out"
        naming.suffix = "-{preset}-v"
        XCTAssertEqual(naming.proposed(input: "/p/a.png", ext: "png", preset: "gray"), "/out/a-gray-v.png")
        naming.suffix = ""
        XCTAssertEqual(naming.proposed(input: "/p/a.png", ext: "png", preset: "gray"), "/out/a.png")
    }

    func testTemplateOverridesThePolicy() {
        let naming = OutputNaming(policy: .folder, folder: "/out")
        XCTAssertEqual(naming.proposed(input: "/p/a.png", ext: "jpg", preset: "web", template: "{dir}/web/{name}"),
                       "/p/web/a.jpg")
        XCTAssertEqual(naming.proposed(input: "/p/a.png", ext: "jpg", preset: "web", template: "small.{ext}"),
                       "/p/small.jpg", "relative templates are beside the input")
    }

    func testNeverOverwrites() {
        let existing: Set<String> = ["/p/a_gray.png", "/p/a_gray-2.png"]
        XCTAssertEqual(OutputNaming.unique("/p/a_gray.png", exists: existing.contains), "/p/a_gray-3.png")
        XCTAssertEqual(OutputNaming.unique("/p/b.png", exists: existing.contains), "/p/b.png")
        XCTAssertEqual(OutputNaming.unique("/p/a.png", avoiding: ["/p/a.png"], exists: { _ in false }), "/p/a-2.png",
                       "never the input, even with an empty suffix")
        XCTAssertEqual(OutputNaming.unique("/p/noext", taken: ["/p/noext"], exists: { _ in false }), "/p/noext-2")
    }

    func testEmptySuffixNeverWritesOverTheInput() throws {
        let naming = OutputNaming(suffix: "")
        let preset = try XCTUnwrap(PresetCatalog.preset("strip"))
        let commands = try CommandBuilder.plan(preset, values: [:], inputs: ["/p/a.png"], naming: naming,
                                               exists: { $0 == "/p/a.png" })
        XCTAssertEqual(commands.first?.output, "/p/a-2.png")
    }

    func testOutputsInOneBatchDoNotCollide() throws {
        // Two inputs with the same name in the same folder policy land on distinct outputs.
        let naming = OutputNaming(policy: .folder, folder: "/out")
        let preset = try XCTUnwrap(PresetCatalog.preset("grayscale"))
        let commands = try CommandBuilder.plan(preset, values: [:], inputs: ["/a/x.png", "/b/x.png"], naming: naming,
                                               exists: { _ in false })
        XCTAssertEqual(commands.map(\.output), ["/out/x_gray.png", "/out/x_gray-2.png"])
    }
}
