import Foundation

/// Debug and Release builds are kept apart: own data folder, own socket, own bundle identifiers.
public enum BuildFlavor: String, Sendable, CaseIterable {
    case release
    case debug

    public var appBundleIdentifier: String {
        switch self {
        case .release: "dev.devdev.app"
        case .debug: "dev.devdev.app.debug"
        }
    }

    public var helperBundleIdentifier: String {
        switch self {
        case .release: "dev.devdev.helper"
        case .debug: "dev.devdev.helper.debug"
        }
    }

    /// Name of the folder under `~/Library/Application Support`.
    public var dataFolderName: String {
        switch self {
        case .release: "devdev"
        case .debug: "devdev-debug"
        }
    }

    /// The flavor this code was compiled as.
    public static var compiled: BuildFlavor {
        #if DEBUG
            .debug
        #else
            .release
        #endif
    }

    /// The flavor of the running program: from its bundle identifier when that is one of ours,
    /// otherwise from how it was compiled.
    public static func current(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> BuildFlavor {
        for flavor in BuildFlavor.allCases
        where bundleIdentifier == flavor.appBundleIdentifier || bundleIdentifier == flavor.helperBundleIdentifier {
            return flavor
        }
        return compiled
    }
}

/// Where the Helper keeps its files.
public struct HelperPaths: Sendable, Equatable {
    public var dataFolder: URL

    public init(dataFolder: URL) {
        self.dataFolder = dataFolder
    }

    public init(flavor: BuildFlavor, homeFolder: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.dataFolder = homeFolder
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(flavor.dataFolderName, isDirectory: true)
    }

    public var socketPath: String { dataFolder.appendingPathComponent("helper.sock").path }
    public var configurationFile: URL { dataFolder.appendingPathComponent("configuration.json") }
}
