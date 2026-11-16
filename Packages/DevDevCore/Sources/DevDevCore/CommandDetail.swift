import Foundation

/// The short text beside a Command in the project tree and the menubar panel:
/// how long it has run, how it ended, or that it is Stopped.
public enum CommandDetail {
    public static func short(status: CommandStatus, lastExit: ProcessExit?, startedAt: Date?, now: Date) -> String {
        switch status {
        case .running:
            guard let startedAt else { return "running" }
            return uptime(since: startedAt, now: now)
        case .finished, .crashed:
            if let code = lastExit?.exitCode { return "exit \(code)" }
            if let signal = lastExit?.signal { return "signal \(signal)" }
            return status.label.lowercased()
        case .stopped:
            return "stopped"
        }
    }

    /// "<1m", "38m", "2h 14m", "3d 4h".
    public static func uptime(since start: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start)) / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(String(format: "%02d", minutes % 60))m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}

extension CommandSnapshot {
    public func detail(now: Date) -> String {
        CommandDetail.short(status: status, lastExit: lastExit, startedAt: startedAt, now: now)
    }
}

extension HelperSnapshot {
    /// Commands Running right now, in every Project.
    public var runningCount: Int { projects.reduce(0) { $0 + $1.commands.count { $0.status == .running } } }
    /// Commands Crashed right now, in every Project.
    public var crashedCount: Int { projects.reduce(0) { $0 + $1.commands.count { $0.status == .crashed } } }
}
