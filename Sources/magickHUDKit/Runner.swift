import Foundation

/// Runs jobs: each job's commands one after another on a background thread, each as a plain
/// argv (never a shell). Every change is reported through `update` on `callbackQueue`; cancel
/// stops the running command and skips the rest.
public final class Runner: @unchecked Sendable {
    public let callbackQueue: DispatchQueue
    /// Lines of output kept per item.
    public static let logLimit = 40

    private let lock = NSLock()
    private var cancelled = Set<String>()
    private var running: [String: Process] = [:]

    public init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
    }

    /// Starts `job`. `update` receives the job after every item status change; the last call
    /// has every item finished.
    public func start(_ job: Job, exists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                      update: @escaping @Sendable (Job) -> Void) {
        let queue = callbackQueue
        Thread.detachNewThread { [self] in
            var job = job
            for index in job.items.indices {
                if isCancelled(job.id) {
                    for rest in index..<job.items.count { job.items[rest].status = .cancelled }
                    break
                }
                job.items[index].status = .running
                prepare(&job.items[index], exists: exists)
                let snapshot = job
                queue.async { update(snapshot) }
                execute(&job.items[index], jobID: job.id)
                let after = job
                if index < job.items.count - 1 { queue.async { update(after) } }
            }
            lock.lock()
            job.cancelRequested = cancelled.remove(job.id) != nil
            lock.unlock()
            let final = job
            queue.async { update(final) }
        }
    }

    public func cancel(_ jobID: String) {
        lock.lock()
        cancelled.insert(jobID)
        let process = running[jobID]
        lock.unlock()
        process?.terminate()
    }

    private func isCancelled(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled.contains(id)
    }

    /// Creates the output folder, and renames the output if a file appeared there since planning.
    private func prepare(_ item: inout JobItem, exists: (String) -> Bool) {
        let output = item.command.output
        try? FileManager.default.createDirectory(atPath: (output as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        guard exists(output) else { return }
        let fresh = OutputNaming.unique(output, avoiding: Set(item.command.inputs), exists: exists)
        if let last = item.command.argv.lastIndex(of: output) { item.command.argv[last] = fresh }
        item.command.output = fresh
    }

    private func execute(_ item: inout JobItem, jobID: String) {
        let argv = item.command.argv
        guard let first = argv.first, let executable = Executables.path(first) else {
            item.status = .failed
            item.exitCode = 127
            item.error = "\(argv.first ?? "magick") not found; install it with `brew install imagemagick`"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(argv.dropFirst())
        process.environment = Executables.childEnvironment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        lock.lock()
        let cancelledBeforeLaunch = cancelled.contains(jobID)
        if !cancelledBeforeLaunch { running[jobID] = process }
        lock.unlock()
        if cancelledBeforeLaunch { item.status = .cancelled; return }
        do {
            try process.run()
        } catch {
            lock.lock(); running[jobID] = nil; lock.unlock()
            item.status = .failed
            item.exitCode = 126
            item.error = "failed to launch \(executable): \(error.localizedDescription)"
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        lock.lock()
        running[jobID] = nil
        let wasCancelled = cancelled.contains(jobID)
        lock.unlock()

        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        item.log = Array(lines.suffix(Self.logLimit))
        item.exitCode = process.terminationStatus
        if wasCancelled && process.terminationReason == .uncaughtSignal {
            item.status = .cancelled
            // A half-written file is not a result.
            try? FileManager.default.removeItem(atPath: item.command.output)
        } else if process.terminationStatus == 0 {
            item.status = .done
        } else {
            item.status = .failed
            item.error = lines.last ?? "\(first) exited with status \(process.terminationStatus)"
        }
    }
}
