import Foundation

/// One process `php artisan dev:list` lists.
public struct DevListProcess: Codable, Sendable, Equatable {
    public var name: String
    public var command: String

    public init(name: String, command: String) {
        self.name = name
        self.command = command
    }
}

/// How one run of `php artisan dev:list --json` went.
public enum DevListRun: Sendable, Equatable {
    case finished(exitCode: Int32, stdout: Data)
    case timedOut
    case failedToStart(String)
}

/// Runs `php artisan dev:list --json` in a Project folder. Tests feed fixture output instead.
public protocol DevListRunner: Sendable {
    func run(in folder: URL) async -> DevListRun
}

public enum DevList {
    /// The line Discovery runs. `--json` prints one JSON array, the same with or without a terminal.
    public static let commandLine = "php artisan dev:list --json"

    /// The listed processes, or nil when Discovery must use the fixed list instead: a non-zero exit,
    /// a timeout, or output that is not a JSON array. An empty array is an answer.
    public static func processes(from run: DevListRun) -> [DevListProcess]? {
        guard case .finished(let exitCode, let stdout) = run, exitCode == 0 else { return nil }
        // A login shell may print its own lines first, so the list is the last line that parses.
        let lines = String(decoding: stdout, as: UTF8.self).split(whereSeparator: \.isNewline)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            guard let listed = try? JSONDecoder().decode([Entry].self, from: Data(trimmed.utf8)) else { continue }
            return listed.compactMap { entry in
                let command = entry.command.trimmingCharacters(in: .whitespaces)
                guard !command.isEmpty, !isCombinedDev(command) else { return nil }
                let name = entry.name?.trimmingCharacters(in: .whitespaces) ?? ""
                return DevListProcess(name: name.isEmpty ? command : name, command: command)
            }
        }
        return nil
    }

    /// `php artisan dev` starts every process as one. Discovery never proposes it.
    static func isCombinedDev(_ command: String) -> Bool {
        command.split(separator: " ").map(String.init) == ["php", "artisan", "dev"]
    }

    private struct Entry: Decodable {
        var command: String
        var name: String?
    }
}

/// Runs `dev:list` through a shell in its own process group, and kills the group on timeout.
public struct ShellDevListRunner: DevListRunner {
    public var shell: Shell
    public var commandLine: String
    public var timeout: Duration

    public init(shell: Shell = .userLogin(), commandLine: String = DevList.commandLine, timeout: Duration = .seconds(20)) {
        self.shell = shell
        self.commandLine = commandLine
        self.timeout = timeout
    }

    public func run(in folder: URL) async -> DevListRun {
        var pipe: [Int32] = [0, 0]
        guard Darwin.pipe(&pipe) == 0 else { return .failedToStart("no pipe: \(String(cString: strerror(errno)))") }
        let (readEnd, writeEnd) = (pipe[0], pipe[1])

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeEnd, 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir(&actions, folder.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setpgroup(&attributes, 0)
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        posix_spawnattr_setflags(&attributes, Int16(flags))

        var argv: [UnsafeMutablePointer<CChar>?] = ([shell.executable] + shell.arguments + [commandLine]).map { strdup($0) }
        argv.append(nil)
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, shell.executable, &actions, &attributes, argv, environ)
        close(writeEnd)
        guard result == 0 else {
            close(readEnd)
            return .failedToStart("\(shell.executable): \(String(cString: strerror(result)))")
        }

        let state = RunState()
        let group = pid
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) {
            if state.markTimedOutUnlessDone() { kill(-group, SIGKILL) }
        }
        let (stdout, status) = await withCheckedContinuation { (continuation: CheckedContinuation<(Data, Int32), Never>) in
            Thread.detachNewThread {
                var status: Int32 = 0
                while waitpid(group, &status, 0) == -1, errno == EINTR {}
                // Anything the shell left behind would hold the pipe open.
                kill(-group, SIGKILL)
                state.setStatus(status)
            }
            Thread.detachNewThread {
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 16_384)
                while true {
                    let count = read(readEnd, &buffer, buffer.count)
                    if count > 0 {
                        // Far more than any list. Past it the output is not a list anyway.
                        if data.count < 4_000_000 { data.append(contentsOf: buffer[0..<count]) }
                    } else if count == 0 || errno != EINTR {
                        break
                    }
                }
                close(readEnd)
                continuation.resume(returning: (data, state.waitForStatus()))
            }
        }
        if state.finish() { return .timedOut }
        return .finished(exitCode: ProcessExit(waitStatus: status).exitCode ?? -1, stdout: stdout)
    }

    private final class RunState: @unchecked Sendable {
        private let condition = NSCondition()
        private var done = false
        private var timedOut = false
        private var status: Int32?

        /// True when the run was still going, so the caller kills it.
        func markTimedOutUnlessDone() -> Bool {
            condition.withLock {
                guard !done else { return false }
                timedOut = true
                return true
            }
        }

        func setStatus(_ value: Int32) {
            condition.withLock {
                status = value
                done = true
                condition.broadcast()
            }
        }

        func waitForStatus() -> Int32 {
            condition.withLock {
                while status == nil { condition.wait() }
                return status ?? 0
            }
        }

        /// Marks the run done. True when it had timed out.
        func finish() -> Bool {
            condition.withLock {
                done = true
                return timedOut
            }
        }
    }
}
