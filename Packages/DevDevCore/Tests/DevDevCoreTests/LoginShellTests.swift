import Foundation
import Testing

@testable import DevDevCore

/// The one place that runs the user's real login shell. Every other process test uses `/bin/sh`.
@Suite struct LoginShellTests {
    @Test func theUserLoginShellIsTheirShellAsALoginInteractiveShellThatTakesTheCommandLineAsAString() {
        #expect(
            Shell.userLogin(environment: ["SHELL": "/opt/homebrew/bin/fish"])
                == Shell(executable: "/opt/homebrew/bin/fish", arguments: ["-l", "-i", "-c"]))
        #expect(Shell.userLogin(environment: [:]) == Shell(executable: "/bin/zsh", arguments: ["-l", "-i", "-c"]))
        #expect(Shell.userLogin(environment: ["SHELL": ""]).executable == "/bin/zsh")
    }

    @Test func aCommandRunsThroughTheUsersLoginShellWithAPseudoTerminal() async throws {
        let shell = Shell.userLogin()
        let name = URL(fileURLWithPath: shell.executable).lastPathComponent
        // How each shell says that it is a login shell. Other shells are only checked for the rest.
        let loginCheck: String? =
            switch name {
            case "zsh": "[[ -o login ]] && echo devdev-login=yes"
            case "bash": "shopt -q login_shell && echo devdev-login=yes"
            default: nil
            }
        let line = [
            "DEVDEV_INLINE=works sh -c 'echo devdev-inline=$DEVDEV_INLINE'",
            "[ -t 0 ] && [ -t 1 ] && echo devdev-terminal=yes",
            "case $- in *i*) echo devdev-interactive=yes;; esac",
            loginCheck ?? "true",
            "echo devdev-ready",
            "sleep 300",
        ].joined(separator: "; ")

        try await withHarness([CommandSettings(name: "Main", commandLine: line)], shell: shell) { h in
            let started = try await h.engine.start(h.first, origin: .user)
            let pid = try #require(started.processID)
            try await waitUntil("the login shell ran the command line", timeout: .seconds(60)) {
                try await h.plainOutput(h.first).contains("devdev-ready")
            }
            let output = try await h.plainOutput(h.first)
            // A variable assignment in front of the command works unchanged: the line is not wrapped in exec.
            #expect(output.contains("devdev-inline=works"))
            #expect(output.contains("devdev-terminal=yes"))
            #expect(output.contains("devdev-interactive=yes"))
            if loginCheck != nil {
                #expect(output.contains("devdev-login=yes"))
            }
            // The Process leads its own session and process group.
            #expect(getsid(pid) == pid)
            #expect(getpgid(pid) == pid)

            let stopped = try await h.engine.stop(h.first, origin: .user)
            #expect(stopped.status == .stopped)
            #expect(!processIsAlive(pid))
        }
    }
}
