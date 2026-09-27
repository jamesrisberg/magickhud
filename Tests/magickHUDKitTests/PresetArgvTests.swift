@testable import magickHUDKit
import XCTest

/// The exact argv every preset makes. Paths are fixed and `exists` is stubbed, so nothing
/// touches the disk.
final class PresetArgvTests: XCTestCase {
    let input = "/pics/photo.png"
    let none: (String) -> Bool = { _ in false }

    private func argv(_ id: String, _ values: [String: String] = [:], inputs: [String]? = nil,
                      defaults: [String: String] = ["quality": "85"]) throws -> [String] {
        let preset = try XCTUnwrap(PresetCatalog.preset(id), id)
        let commands = try CommandBuilder.plan(preset, values: values, inputs: inputs ?? [input],
                                               defaults: defaults, exists: none)
        return try XCTUnwrap(commands.first).argv
    }

    func testCatalogHasEveryOperation() {
        let ids = Set(PresetCatalog.all.map(\.id))
        // Every built-in preset id.
        for id in ["resize", "convert", "compress", "crop", "rotate", "strip", "grayscale", "blur", "sharpen",
                   "border", "watermark", "montage", "custom", "adjust", "web", "thumbnail", "trim"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertEqual(ids.count, PresetCatalog.all.count, "ids are unique")
    }

    func testResize() throws {
        XCTAssertEqual(try argv("resize"), ["magick", input, "-resize", "50%", "/pics/photo_resized.png"])
        XCTAssertEqual(try argv("resize", ["size": "1920x"])[2...3], ["-resize", "1920x"])
        XCTAssertEqual(try argv("resize", ["width": "32"])[3], "32x")
        XCTAssertEqual(try argv("resize", ["height": "600"])[3], "x600")
        XCTAssertEqual(try argv("resize", ["width": "800", "height": "600", "fit": "exact"])[3], "800x600!")
        XCTAssertEqual(try argv("resize", ["width": "800", "height": "600", "fit": "fill"])[3], "800x600^")
        XCTAssertEqual(try argv("resize", ["width": "800", "fit": "shrink"])[3], "800x>")
        XCTAssertEqual(try argv("resize", ["width": "800", "fit": "exact"])[3], "800x", "exact needs both sides")
        XCTAssertThrowsError(try argv("resize", ["width": "wide"]))
    }

    func testConvert() throws {
        XCTAssertEqual(try argv("convert"), ["magick", input, "-quality", "85", "/pics/photo_converted.jpg"])
        XCTAssertEqual(try argv("convert", ["format": "webp", "quality": "60"]),
                       ["magick", input, "-quality", "60", "/pics/photo_converted.webp"])
        XCTAssertEqual(try argv("convert", ["format": "png"]), ["magick", input, "/pics/photo_converted.png"],
                       "lossless formats take no quality")
        XCTAssertEqual(try argv("convert", ["format": "pdf"]).last, "/pics/photo_converted.pdf")
        XCTAssertThrowsError(try argv("convert", ["format": "bmp9"]))
        XCTAssertThrowsError(try argv("convert", ["quality": "101"]))
    }

    func testCompressUsesTheSettingsQuality() throws {
        XCTAssertEqual(try argv("compress", defaults: ["quality": "70"]),
                       ["magick", input, "-strip", "-quality", "70", "/pics/photo_compressed.png"])
        XCTAssertEqual(try argv("compress", ["strip": "0", "quality": "50"]),
                       ["magick", input, "-quality", "50", "/pics/photo_compressed.png"])
    }

    func testWeb() throws {
        XCTAssertEqual(try argv("web"), ["magick", input, "-auto-orient", "-resize", "1920x1920>", "-strip",
                                         "-quality", "85", "/pics/photo_web.jpg"])
        XCTAssertEqual(try argv("web", ["format": "keep", "max": "800"]),
                       ["magick", input, "-auto-orient", "-resize", "800x800>", "-strip", "/pics/photo_web.png"])
    }

    func testThumbnail() throws {
        XCTAssertEqual(try argv("thumbnail", ["size": "150"]),
                       ["magick", input, "-auto-orient", "-thumbnail", "150x150^", "-gravity", "center",
                        "-extent", "150x150", "/pics/photo_thumb.png"])
    }

    func testCrop() throws {
        XCTAssertEqual(try argv("crop"), ["magick", input, "-gravity", "center", "-crop", "1:1", "+repage",
                                          "/pics/photo_cropped.png"])
        XCTAssertEqual(try argv("crop", ["aspect": "16:9", "gravity": "north"])[2...6],
                       ["-gravity", "north", "-crop", "16:9", "+repage"])
        XCTAssertEqual(try argv("crop", ["aspect": "custom", "geometry": "800x600+100+50"]),
                       ["magick", input, "-crop", "800x600+100+50", "+repage", "/pics/photo_cropped.png"])
        XCTAssertThrowsError(try argv("crop", ["aspect": "custom"]))
    }

    func testTrim() throws {
        XCTAssertEqual(try argv("trim"), ["magick", input, "-fuzz", "5%", "-trim", "+repage", "/pics/photo_trimmed.png"])
    }

    func testRotate() throws {
        XCTAssertEqual(try argv("rotate"), ["magick", input, "-rotate", "90", "/pics/photo_rotated.png"])
        XCTAssertEqual(try argv("rotate", ["rotation": "-90"])[2...3], ["-rotate", "-90"])
        XCTAssertEqual(try argv("rotate", ["rotation": "180"])[3], "180")
        XCTAssertEqual(try argv("rotate", ["rotation": "flip"])[2], "-flip")
        XCTAssertEqual(try argv("rotate", ["rotation": "flop"])[2], "-flop")
        XCTAssertEqual(try argv("rotate", ["rotation": "auto"])[2], "-auto-orient")
    }

    func testStripAndGrayscale() throws {
        XCTAssertEqual(try argv("strip"), ["magick", input, "-strip", "/pics/photo_stripped.png"])
        XCTAssertEqual(try argv("grayscale"), ["magick", input, "-colorspace", "Gray", "/pics/photo_gray.png"])
    }

    func testAdjust() throws {
        XCTAssertEqual(try argv("adjust", ["brightness": "10"]),
                       ["magick", input, "-brightness-contrast", "10x0", "/pics/photo_adjusted.png"])
        XCTAssertEqual(try argv("adjust", ["contrast": "-5", "saturation": "120"]),
                       ["magick", input, "-brightness-contrast", "0x-5", "-modulate", "100,120,100",
                        "/pics/photo_adjusted.png"])
        XCTAssertThrowsError(try argv("adjust"), "nothing to adjust")
    }

    func testBlurAndSharpen() throws {
        XCTAssertEqual(try argv("blur"), ["magick", input, "-blur", "0x2", "/pics/photo_blurred.png"])
        XCTAssertEqual(try argv("blur", ["sigma": "3x1.5"])[3], "3x1.5")
        XCTAssertEqual(try argv("sharpen"), ["magick", input, "-sharpen", "0x1", "/pics/photo_sharpened.png"])
    }

    func testBorder() throws {
        XCTAssertEqual(try argv("border", ["width": "4", "color": "#222"]),
                       ["magick", input, "-bordercolor", "#222", "-border", "4", "/pics/photo_border.png"])
    }

    func testWatermark() throws {
        XCTAssertEqual(try argv("watermark", ["text": "© 2026 J; rm -rf /"]),
                       ["magick", input, "-gravity", "southeast", "-fill", "rgba(255,255,255,0.6)",
                        "-pointsize", "24", "-annotate", "+16+16", "© 2026 J; rm -rf /",
                        "/pics/photo_watermarked.png"], "text is one argv element, never shell-parsed")
        XCTAssertThrowsError(try argv("watermark"), "text is required")
    }

    func testMontageCombinesEveryInput() throws {
        let inputs = ["/pics/a.png", "/pics/b.jpg", "/other/c.png"]
        XCTAssertEqual(try argv("montage", inputs: inputs),
                       ["magick", "montage", "/pics/a.png", "/pics/b.jpg", "/other/c.png", "-tile", "4x",
                        "-geometry", "256x256+4+4", "-background", "#222222", "/pics/contact-sheet.png"])
        let labelled = try argv("montage", ["labels": "1", "columns": "2", "format": "jpg"], inputs: inputs)
        XCTAssertEqual(Array(labelled[0...4]), ["magick", "montage", "-label", "%f", "-fill"])
        XCTAssertEqual(labelled.last, "/pics/contact-sheet.jpg")
        let preset = try XCTUnwrap(PresetCatalog.preset("montage"))
        XCTAssertEqual(try CommandBuilder.plan(preset, values: [:], inputs: inputs, exists: none).count, 1)
    }

    func testCustomArgsWithTokens() throws {
        XCTAssertEqual(try argv("custom", ["args": "-resize 50% -strip"]),
                       ["magick", input, "-resize", "50%", "-strip", "/pics/photo_custom.png"])
        XCTAssertEqual(try argv("custom", ["args": "{input}[0] -set comment '{name} from {dir}' {output}", "ext": "jpg"]),
                       ["magick", "/pics/photo.png[0]", "-set", "comment", "photo from /pics", "/pics/photo_custom.jpg"])
        XCTAssertThrowsError(try argv("custom"), "args are required")
        XCTAssertThrowsError(try argv("custom", ["args": "-annotate +0+0 'open"]))
    }

    func testBatchMakesOneCommandPerInputWithDistinctOutputs() throws {
        let preset = try XCTUnwrap(PresetCatalog.preset("grayscale"))
        let commands = try CommandBuilder.plan(preset, values: [:], inputs: ["/a/x.png", "/b/y.jpg", "~/z.png"], exists: none)
        XCTAssertEqual(commands.map(\.output), ["/a/x_gray.png", "/b/y_gray.jpg",
                                                (("~/z_gray.png") as NSString).expandingTildeInPath])
        XCTAssertThrowsError(try CommandBuilder.plan(preset, values: [:], inputs: [], exists: none)) {
            XCTAssertEqual($0 as? BuildError, .noInput)
        }
    }

    func testEverySelectDefaultIsOneOfItsOptions() {
        for preset in PresetCatalog.all {
            for field in preset.fields where field.kind == .select {
                XCTAssertTrue(field.options.contains { $0.value == field.defaultValue }, "\(preset.id).\(field.id)")
            }
        }
    }

    func testSearch() {
        XCTAssertEqual(PresetCatalog.search("exif gps").map(\.id), ["strip"])
        XCTAssertTrue(PresetCatalog.search("WEBP").map(\.id).contains("convert"))
        XCTAssertEqual(PresetCatalog.search("").count, PresetCatalog.all.count)
        XCTAssertTrue(PresetCatalog.search("zzz").isEmpty)
    }

    func testDisplayQuotesForTheShell() {
        let command = MagickCommand(argv: ["magick", "/a b/it's.png", "-resize", "50%", "/x.png"], inputs: [], output: "/x.png")
        XCTAssertEqual(command.display, "magick '/a b/it'\\''s.png' -resize 50% /x.png")
    }

    func testSplit() throws {
        XCTAssertEqual(try CommandBuilder.split(#"  -a "b c"  'd "e"' f\ g "#), ["-a", "b c", #"d "e""#, "f g"])
        XCTAssertEqual(try CommandBuilder.split(""), [])
        XCTAssertEqual(try CommandBuilder.split("''"), [""])
    }
}
