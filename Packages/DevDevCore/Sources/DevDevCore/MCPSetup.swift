import Foundation

/// Where the `devdev` CLI sits, and the line Settings shows for adding it to Claude Code.
public enum MCPSetup {
    /// The CLI inside an App bundle. `Contents/MacOS/devdev` is the App itself, so the CLI sits beside the Helper.
    public static let cliPathInApp = "Contents/Helpers/devdev"

    /// Release: inside `/Applications/devdev.app`, whichever copy runs. Debug: inside the running App.
    public static func cliExecutable(flavor: BuildFlavor, appBundle: URL) -> URL {
        let app = flavor == .release ? HelperLocation.installedApp : appBundle
        return app.appendingPathComponent(cliPathInApp, isDirectory: false)
    }

    /// The name the server is added under. A Debug build gets its own, so it never replaces the daily one.
    public static func serverName(flavor: BuildFlavor) -> String {
        flavor == .release ? "devdev" : "devdev-debug"
    }

    /// `claude mcp add devdev -- "<path>" mcp`, ready to paste into a shell.
    public static func line(flavor: BuildFlavor, appBundle: URL) -> String {
        let path = cliExecutable(flavor: flavor, appBundle: appBundle).path
        return "claude mcp add \(serverName(flavor: flavor)) -- \"\(doubleQuoted(path))\" mcp"
    }

    /// The App bundle the CLI sits in: `<App>.app/Contents/Helpers/devdev`. A CLI that sits in no App,
    /// such as one in an Xcode products folder, uses the `devdev.app` beside it.
    public static func app(containingCLI cli: URL) -> URL {
        let helpers = cli.standardizedFileURL.deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        if helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents", app.pathExtension == "app" {
            return app
        }
        return helpers.appendingPathComponent("devdev.app", isDirectory: true)
    }

    /// Escapes the characters a shell still reads inside double quotes.
    private static func doubleQuoted(_ text: String) -> String {
        var out = ""
        for character in text {
            if "\"\\$`".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }
}
