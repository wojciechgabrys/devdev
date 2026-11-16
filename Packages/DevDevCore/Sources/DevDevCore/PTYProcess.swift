import Foundation

/// What to run, and where.
struct ProcessSpec: Sendable {
    var executable: String
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: String
    var size: TerminalSize
}

enum ProcessEvent: Sendable {
    case output(Data)
    /// Always the last event. `killed` is true when the stop had to send SIGKILL.
    case ended(ProcessExit, killed: Bool)
}

struct ProcessStartError: Error, CustomStringConvertible {
    var description: String
}

/// One Process: a child on a pseudo-terminal that leads its own session and process group.
final class PTYProcess: @unchecked Sendable {
    let pid: pid_t
    let events: AsyncStream<ProcessEvent>

    private let continuation: AsyncStream<ProcessEvent>.Continuation
    private let queue: DispatchQueue
    private let master: Int32
    private var readSource: DispatchSourceRead?
    private var masterOpen = true
    private var leaderExit: ProcessExit?
    private var terminating = false
    private var killed = false
    private var giveUpAt: DispatchTime?
    private var finished = false

    /// `_IOW('t', 103, struct winsize)`. The C macro is not visible from Swift.
    private static let setWindowSize: UInt = 0x8008_7467

    static func spawn(_ spec: ProcessSpec) throws -> PTYProcess {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: spec.workingDirectory, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ProcessStartError(description: "the folder \(spec.workingDirectory) does not exist")
        }

        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { throw ProcessStartError(description: "no pseudo-terminal: \(errnoText())") }
        // `ptsname` shares one buffer between threads, so use the variant that fills ours.
        var name = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard grantpt(master) == 0, unlockpt(master) == 0, ptsname_r(master, &name, name.count) == 0 else {
            let text = errnoText()
            close(master)
            throw ProcessStartError(description: "no pseudo-terminal: \(text)")
        }
        let terminalPath = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        // The size only sticks while the terminal is open, so hold it open until the child has it.
        let terminal = open(terminalPath, O_RDWR | O_NOCTTY)
        defer { if terminal >= 0 { close(terminal) } }
        var size = winsize(ws_row: spec.size.rows, ws_col: spec.size.columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, setWindowSize, &size)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        // The child leads a new session, so opening the terminal makes it the controlling terminal.
        posix_spawn_file_actions_addopen(&actions, 0, terminalPath, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&actions, 0, 1)
        posix_spawn_file_actions_adddup2(&actions, 0, 2)
        posix_spawn_file_actions_addchdir(&actions, spec.workingDirectory)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        posix_spawnattr_setflags(&attributes, Int16(flags))

        var argv: [UnsafeMutablePointer<CChar>?] = ([spec.executable] + spec.arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = spec.environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, spec.executable, &actions, &attributes, argv, envp)
        guard result == 0 else {
            close(master)
            throw ProcessStartError(description: "\(spec.executable): \(String(cString: strerror(result)))")
        }
        return PTYProcess(pid: pid, master: master)
    }

    private init(pid: pid_t, master: Int32) {
        self.pid = pid
        self.master = master
        self.queue = DispatchQueue(label: "dev.devdev.process.\(pid)")
        (events, continuation) = AsyncStream.makeStream(of: ProcessEvent.self)

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { close(master) }
        readSource = source
        source.resume()

        Thread.detachNewThread { [self] in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1, errno == EINTR {}
            let exit = ProcessExit(waitStatus: status)
            queue.async { self.leaderEnded(exit) }
        }
    }

    /// Sends SIGTERM to the whole tree, then SIGKILL after `escalateAfter` if anything still lives.
    func terminate(escalateAfter: Duration) {
        queue.async { [self] in
            guard !finished, !terminating else { return }
            terminating = true
            signalTree(SIGTERM)
            queue.asyncAfter(deadline: .now() + escalateAfter.timeInterval) { [self] in
                guard !finished else { return }
                killed = true
                giveUpAt = .now() + 2
                signalTree(SIGKILL)
            }
            if leaderExit != nil { finishWhenTreeIsGone() }
        }
    }

    func resize(_ size: TerminalSize) {
        queue.async { [self] in
            guard masterOpen else { return }
            var size = winsize(ws_row: size.rows, ws_col: size.columns, ws_xpixel: 0, ws_ypixel: 0)
            _ = ioctl(master, Self.setWindowSize, &size)
        }
    }

    // MARK: - On the queue

    private func drain() {
        guard masterOpen else { return }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(master, &buffer, buffer.count)
            if count > 0 {
                continuation.yield(.output(Data(buffer[0..<count])))
            } else if count == -1, errno == EINTR {
                continue
            } else if count == -1, errno == EAGAIN {
                return
            } else {
                closeMaster()
                return
            }
        }
    }

    private func closeMaster() {
        guard masterOpen else { return }
        masterOpen = false
        readSource?.cancel()
    }

    private func leaderEnded(_ exit: ProcessExit) {
        leaderExit = exit
        drain()
        if terminating {
            finishWhenTreeIsGone()
        } else {
            // Ended by itself. Anything it left behind loses its terminal, as when a terminal window closes.
            signalTree(SIGHUP)
            finish()
        }
    }

    private func finishWhenTreeIsGone() {
        guard !finished else { return }
        let gaveUp = giveUpAt.map { DispatchTime.now() >= $0 } ?? false
        if gaveUp || treeMembers().isEmpty {
            finish()
        } else {
            queue.asyncAfter(deadline: .now() + 0.02) { [self] in finishWhenTreeIsGone() }
        }
    }

    private func finish() {
        guard !finished, let leaderExit else { return }
        finished = true
        drain()
        closeMaster()
        continuation.yield(.ended(leaderExit, killed: killed))
        continuation.finish()
    }

    /// Every live process in the session the child leads, apart from the child itself once it is reaped.
    /// An interactive shell puts its jobs in process groups of their own, so the leader's group is not enough.
    private func treeMembers() -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 128)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(0, count))).filter { $0 > 1 && getsid($0) == pid }
    }

    private func signalTree(_ signal: Int32) {
        var groups = Set(treeMembers().map { getpgid($0) }.filter { $0 > 1 })
        if leaderExit == nil { groups.insert(pid) }
        for group in groups {
            kill(-group, signal)
        }
    }

    private static func errnoText() -> String { String(cString: strerror(errno)) }
}

extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
