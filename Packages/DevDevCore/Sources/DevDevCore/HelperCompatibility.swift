import CryptoKit
import Foundation

/// How the running Helper compares with the one this App expects.
public enum HelperCompatibility: Sendable, Equatable {
    /// Same protocol version and same build.
    case current
    /// Another build that speaks the same protocol. The App keeps working against it.
    case outdated
    /// Another protocol version. The App must not send it requests.
    case incompatible(helperProtocol: Int, appProtocol: Int)

    public static func evaluate(
        appProtocol: Int, appBuild: String, helperProtocol: Int, helperBuild: String
    ) -> HelperCompatibility {
        if helperProtocol != appProtocol {
            return .incompatible(helperProtocol: helperProtocol, appProtocol: appProtocol)
        }
        return helperBuild == appBuild ? .current : .outdated
    }

    /// False when the App cannot safely talk to this Helper.
    public var allowsRequests: Bool {
        if case .incompatible = self { false } else { true }
    }
}

/// Names one build of the Helper, so a replaced app can tell that an older Helper still runs.
public enum HelperBuild {
    /// The version plus a hash of the executable's bytes. Just the version when the file cannot be read.
    public static func identifier(ofExecutableAt url: URL?) -> String {
        guard let url, let bytes = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return DevDevCore.version
        }
        let hash = SHA256.hash(data: bytes).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(DevDevCore.version)+\(hash)"
    }
}

/// Where the App finds the Helper it starts.
public struct HelperLocation: Sendable, Equatable {
    /// The daily app. A Release build always starts the Helper inside it.
    public static let installedApp = URL(fileURLWithPath: "/Applications/devdev.app", isDirectory: true)

    public var flavor: BuildFlavor
    /// The bundle of the running App.
    public var appBundle: URL

    public init(flavor: BuildFlavor, appBundle: URL) {
        self.flavor = flavor
        self.appBundle = appBundle
    }

    /// Release: inside `/Applications/devdev.app`. Debug: inside the running App, never the installed one.
    public var helperBundle: URL {
        let app = flavor == .release ? Self.installedApp : appBundle
        return app.appendingPathComponent("Contents/Helpers/devdevHelper.app", isDirectory: true)
    }

    public var helperExecutable: URL {
        helperBundle.appendingPathComponent("Contents/MacOS/devdevHelper", isDirectory: false)
    }

    /// The Helper bundle, or an error that says how to get one.
    public func existingHelperBundle(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> URL {
        guard fileExists(helperExecutable.path) else {
            let advice =
                flavor == .release
                ? "Run scripts/install.sh to install devdev in /Applications." : "Build the devdev scheme again."
            throw HelperError(
                code: HelperError.connectionFailed,
                message: "There is no Helper at \(helperBundle.path). \(advice)")
        }
        return helperBundle
    }
}
