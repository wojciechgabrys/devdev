/// The logic shared by the App, the Helper and the `devdev` CLI.
public enum DevDevCore {
    public static let version = "0.2.1"

    /// The version line of the About window. The build number equals the version, so it is
    /// shown only when a build breaks that rule.
    public static func versionLabel(short: String, build: String) -> String {
        build == short ? "Version \(short)" : "Version \(short) (\(build))"
    }
}
