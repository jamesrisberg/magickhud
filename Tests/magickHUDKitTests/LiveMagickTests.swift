@testable import magickHUDKit
import XCTest

/// Runs every preset for real on a generated 64×64 PNG in a temp folder. Skipped when ImageMagick
/// is not installed.
final class LiveMagickTests: XCTestCase {
    func testEveryPresetRunsWithImageMagick() throws {
        guard let magick = Executables.magick() else { throw XCTSkip("magick is not installed") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("magickhud-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let red = dir.appendingPathComponent("red.png").path
        let blue = dir.appendingPathComponent("blue.png").path
        XCTAssertNotNil(Identify.run([magick, "-size", "64x48", "xc:red", red]))
        XCTAssertNotNil(Identify.run([magick, "-size", "32x32", "xc:blue", blue]))

        let info = try XCTUnwrap(Identify.info(red, binary: magick))
        XCTAssertEqual(info.format, "PNG")
        XCTAssertEqual(info.dimensions, "64×48")
        XCTAssertEqual(Identify.info(red, binary: nil)?.dimensions, "64×48", "ImageIO fallback")

        let values: [String: [String: String]] = [
            "adjust": ["brightness": "10"], "watermark": ["text": "hi"], "custom": ["args": "-negate"],
            "convert": ["format": "webp"], "resize": ["width": "32"],
        ]
        for preset in PresetCatalog.all {
            let inputs = preset.combinesInputs ? [red, blue] : [red]
            let commands = try CommandBuilder.plan(preset, values: values[preset.id] ?? [:], inputs: inputs, binary: magick)
            let job = Job(id: preset.id, preset: preset, commands: commands)
            let done = expectation(description: preset.id)
            let final = Locked<Job?>(nil)
            Runner(callbackQueue: DispatchQueue(label: preset.id)).start(job) { job in
                if job.items.allSatisfy(\.isFinished) { final.with { $0 = job }; done.fulfill() }
            }
            wait(for: [done], timeout: 30)
            XCTAssertEqual(final.get?.state, .done, "\(preset.id): \(final.get?.items.first?.log ?? [])")
            XCTAssertTrue(FileManager.default.fileExists(atPath: commands[0].output), preset.id)
        }
        let resized = try XCTUnwrap(Identify.info(dir.appendingPathComponent("red_resized.png").path, binary: magick))
        XCTAssertEqual(resized.dimensions, "32×24")
        XCTAssertEqual(Identify.info(dir.appendingPathComponent("red_cropped.png").path, binary: magick)?.dimensions, "48×48")
    }
}
