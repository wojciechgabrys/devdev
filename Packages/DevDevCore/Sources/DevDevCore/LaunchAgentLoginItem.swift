import Foundation

/// Launch at login through a file in `~/Library/LaunchAgents`.
///
/// The login-item API stops working after every reinstall of an ad hoc signed build
/// (`docs/spike-results.md` item 3), so this is the fallback. Writing or deleting the file never starts
/// or stops a Helper now: launchd reads it at the next login. The agent runs the Helper with no
/// arguments and no `KeepAlive`, so it starts no Process and Stop All and Quit stays quit.
public struct LaunchAgentLoginItem: LoginItem {
    public var label: String
    public var executable: URL
    public var file: URL

    public init(label: String, executable: URL, folder: URL) {
        self.label = label
        self.executable = executable
        self.file = folder.appendingPathComponent("\(label).plist", isDirectory: false)
    }

    /// The agent for this Helper. Release runs the Helper inside `/Applications/devdev.app`; Debug runs
    /// the Debug Helper that asked, under its own label, so it never touches the installed one.
    public static func forHelper(
        flavor: BuildFlavor,
        runningHelperExecutable: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> LaunchAgentLoginItem {
        let executable =
            flavor == .release
            ? HelperLocation(flavor: .release, appBundle: HelperLocation.installedApp).helperExecutable
            : runningHelperExecutable
        return LaunchAgentLoginItem(
            label: flavor.helperBundleIdentifier,
            executable: executable,
            folder: home.appendingPathComponent("Library/LaunchAgents", isDirectory: true))
    }

    public func apply(enabled: Bool) throws {
        if enabled {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let contents: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable.path],
                "RunAtLoad": true,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            try data.write(to: file, options: .atomic)
        } else if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
