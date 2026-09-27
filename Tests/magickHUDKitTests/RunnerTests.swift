@testable import magickHUDKit
import XCTest

/// The runner with stand-in commands (true, false, sleep), so it runs without ImageMagick.
final class RunnerTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("magickhud-runner-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func job(_ argvs: [[String]]) -> Job {
        let preset = PresetCatalog.preset("strip")!
        return Job(id: "j1", preset: preset, commands: argvs.enumerated().map {
            MagickCommand(argv: $0.element, inputs: ["/in\($0.offset).png"], output: dir.appendingPathComponent("out\($0.offset).png").path)
        })
    }

    private func run(_ job: Job, runner: Runner = Runner(callbackQueue: DispatchQueue(label: "t")),
                     during: ((Runner) -> Void)? = nil) -> [Job] {
        let done = expectation(description: "finished")
        let updates = Locked<[Job]>([])
        runner.start(job) { job in
            updates.with { $0.append(job) }
            if !job.isActive, job.items.allSatisfy(\.isFinished) { done.fulfill() }
        }
        during?(runner)
        wait(for: [done], timeout: 10)
        return updates.get
    }

    func testPerFileProgressAndFailures() throws {
        let updates = run(job([["/usr/bin/true"], ["/bin/sh", "-c", "echo boom >&2; exit 3"], ["/usr/bin/true"]]))
        let final = try XCTUnwrap(updates.last)
        XCTAssertEqual(final.items.map(\.status), [.done, .failed, .done])
        XCTAssertEqual(final.items[1].exitCode, 3)
        XCTAssertEqual(final.items[1].error, "boom")
        XCTAssertEqual(final.state, .failed)
        XCTAssertEqual(final.progress, 1)
        XCTAssertTrue(updates.contains { $0.state == .running && $0.finishedCount == 1 }, "progress is reported per file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path), "the output folder is created")
    }

    func testCancelStopsTheRunningCommandAndSkipsTheRest() throws {
        let updates = run(job([["/bin/sleep", "5"], ["/usr/bin/true"]])) { runner in
            Thread.sleep(forTimeInterval: 0.3)
            runner.cancel("j1")
        }
        let final = try XCTUnwrap(updates.last)
        XCTAssertEqual(final.items.map(\.status), [.cancelled, .cancelled])
        XCTAssertEqual(final.state, .cancelled)
    }

    func testMissingBinaryFails() throws {
        let final = try XCTUnwrap(run(job([["definitely-not-a-binary-xyz"]])).last)
        XCTAssertEqual(final.items[0].status, .failed)
        XCTAssertEqual(final.items[0].exitCode, 127)
    }

    func testAnOutputThatAppearedSincePlanningIsNotOverwritten() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let taken = dir.appendingPathComponent("out0.png").path
        try Data("keep".utf8).write(to: URL(fileURLWithPath: taken))
        let final = try XCTUnwrap(run(job([["/usr/bin/touch", taken]])).last)
        XCTAssertEqual(final.items[0].output, dir.appendingPathComponent("out0-2.png").path)
        XCTAssertEqual(final.items[0].command.argv.last, final.items[0].output)
        XCTAssertEqual(try String(contentsOfFile: taken, encoding: .utf8), "keep")
    }
}

/// A value shared with the runner's callback queue.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func with<R>(_ body: (inout Value) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
    var get: Value { with { $0 } }
}
