import Foundation

/// The stored output of one Command: the last lines, bounded by a line count and a byte count.
public struct OutputBuffer: Sendable {
    public static let standardMaxLines = 10_000
    public static let standardMaxBytes = 8 * 1024 * 1024

    public let maxLines: Int
    public let maxBytes: Int

    /// Each element is one line including its "\n". Only the last may lack it.
    private var lines: [Data] = []
    private var byteCount = 0

    public init(maxLines: Int = OutputBuffer.standardMaxLines, maxBytes: Int = OutputBuffer.standardMaxBytes) {
        precondition(maxLines > 0 && maxBytes > 0)
        self.maxLines = maxLines
        self.maxBytes = maxBytes
    }

    public var isEmpty: Bool { byteCount == 0 }
    public var lineCount: Int { lines.count }
    public var bytes: Int { byteCount }

    /// True when the output ends in the middle of a line.
    public var endsMidLine: Bool { lines.last.map { $0.last != 0x0a } ?? false }

    public mutating func append(_ data: Data) {
        var rest = data[...]
        while !rest.isEmpty {
            let end = rest.firstIndex(of: 0x0a).map { rest.index(after: $0) } ?? rest.endIndex
            let piece = rest[rest.startIndex..<end]
            if endsMidLine {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append(Data(piece))
            }
            byteCount += piece.count
            rest = rest[end...]
        }
        trim()
    }

    private mutating func trim() {
        var drop = max(0, lines.count - maxLines)
        var bytesAfter = byteCount - lines[..<drop].reduce(0) { $0 + $1.count }
        while bytesAfter > maxBytes, drop < lines.count - 1 {
            bytesAfter -= lines[drop].count
            drop += 1
        }
        if drop > 0 {
            lines.removeFirst(drop)
            byteCount = bytesAfter
        }
        // One endless line: keep only its tail.
        if byteCount > maxBytes, lines.count == 1 {
            lines[0] = Data(lines[0].suffix(maxBytes))
            byteCount = lines[0].count
        }
    }

    /// The stored output as the Process wrote it, escape sequences included.
    public var data: Data {
        var all = Data(capacity: byteCount)
        for line in lines { all.append(line) }
        return all
    }

    /// The stored output with escape sequences removed. `lastLines` limits it to the newest lines.
    public func plainText(lastLines: Int? = nil) -> String {
        let text = PlainText.strip(data)
        guard let lastLines else { return text }
        var parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        if parts.last == "" { parts.removeLast() }
        return parts.suffix(max(0, lastLines)).joined(separator: "\n")
    }
}

/// The lines devdev itself writes into a Command's output.
public enum OutputBanner {
    public static func restarted(at date: Date, timeZone: TimeZone = .current) -> String {
        "restarted \(clock(date, timeZone))"
    }

    public static func started(at date: Date, timeZone: TimeZone = .current) -> String {
        "started \(clock(date, timeZone))"
    }

    public static func ended(_ exit: ProcessExit) -> String {
        if let code = exit.exitCode { return "exited with code \(code)" }
        return "ended by signal \(exit.signal ?? 0)"
    }

    public static let stopped = "stopped"

    public static func couldNotStart(_ reason: String) -> String { "could not start: \(reason)" }

    /// The bytes for one banner line, dimmed, on a line of its own.
    public static func line(_ text: String, afterPartialLine: Bool) -> Data {
        Data("\(afterPartialLine ? "\r\n" : "")\u{1b}[2m── \(text) ──\u{1b}[0m\r\n".utf8)
    }

    private static func clock(_ date: Date, _ timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
