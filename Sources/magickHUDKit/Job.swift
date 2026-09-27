import Foundation

/// One command of a job and how it went.
public struct JobItem: Equatable, Sendable, Codable, Identifiable {
    public enum Status: String, Codable, Sendable { case pending, running, done, failed, cancelled }

    public var id: Int
    public var command: MagickCommand
    public var status: Status = .pending
    public var exitCode: Int32?
    /// The last lines magick printed (stderr and stdout), for the errors disclosure.
    public var log: [String] = []
    public var error: String?

    public init(id: Int, command: MagickCommand) {
        self.id = id
        self.command = command
    }

    public var input: String { command.inputs.first ?? "" }
    public var output: String { command.output }
    public var isFinished: Bool { [.done, .failed, .cancelled].contains(status) }

    public var json: [String: Any] {
        var d: [String: Any] = ["inputs": command.inputs, "output": command.output,
                                "status": status.rawValue, "argv": command.argv]
        if let exitCode { d["exit"] = Int(exitCode) }
        if let error { d["error"] = error }
        return d
    }
}

/// A preset run over one or more files.
public struct Job: Equatable, Sendable, Codable, Identifiable {
    public enum State: String, Codable, Sendable { case pending, running, done, failed, cancelled }

    public var id: String
    public var presetID: String
    public var title: String
    public var created: Date
    public var items: [JobItem]
    public var cancelRequested = false

    public init(id: String, preset: Preset, commands: [MagickCommand], created: Date = Date()) {
        self.id = id
        presetID = preset.id
        title = preset.title
        self.created = created
        items = commands.enumerated().map { JobItem(id: $0.offset, command: $0.element) }
    }

    public var finishedCount: Int { items.filter(\.isFinished).count }
    public var failedCount: Int { items.filter { $0.status == .failed }.count }
    public var doneCount: Int { items.filter { $0.status == .done }.count }
    /// 0...1, counting finished items.
    public var progress: Double { items.isEmpty ? 1 : Double(finishedCount) / Double(items.count) }

    public var state: State {
        if items.contains(where: { $0.status == .running }) { return .running }
        if !items.allSatisfy(\.isFinished) { return finishedCount == 0 && !cancelRequested ? .pending : .running }
        if items.contains(where: { $0.status == .cancelled }) { return .cancelled }
        if failedCount > 0 { return .failed }
        return .done
    }

    public var isActive: Bool { state == .pending || state == .running }

    /// The outputs that were written.
    public var outputs: [String] { items.filter { $0.status == .done }.map(\.output) }

    /// "Resize 3/5", "Resize: 5 done", "Resize: 1 failed".
    public var statusLine: String {
        switch state {
        case .pending: return "\(title): waiting"
        case .running: return "\(title) \(finishedCount + 1)/\(items.count)"
        case .done: return "\(title): \(doneCount) done"
        case .failed: return "\(title): \(failedCount) failed"
        case .cancelled: return "\(title): cancelled"
        }
    }

    public var json: [String: Any] {
        ["id": id, "preset": presetID, "title": title, "state": state.rawValue,
         "progress": progress, "done": doneCount, "failed": failedCount, "total": items.count,
         "created": ISO8601DateFormatter().string(from: created),
         "outputs": outputs, "items": items.map(\.json)]
    }
}
