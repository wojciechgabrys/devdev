import Foundation

/// One piece of software whose notices devdev.app must carry: DevDev itself, or a Swift package
/// built into the App, the Helper or the `devdev` CLI.
public struct Acknowledgement: Identifiable, Hashable, Sendable {
    /// The package identity in `Package.resolved`, or `devdev` for DevDev itself.
    public let id: String
    public let name: String
    public let url: URL
    /// The license in short form, for the list. The full text is in `files`.
    public let license: String
    /// Text files in the App's Resources, shown in this order: the license, then any NOTICE.
    public let files: [String]

    public init(id: String, name: String, url: URL, license: String, files: [String]) {
        self.id = id
        self.name = name
        self.url = url
        self.license = license
        self.files = files
    }
}

/// What the About window lists. Every package pinned in `Package.resolved` must be here,
/// with its license text and any NOTICE copied verbatim into `App/Acknowledgements/`.
public enum Acknowledgements {
    /// Matches the copyright line in `LICENSE` and the bundles' `NSHumanReadableCopyright`.
    public static let copyright = "Copyright © 2026 Wojciech Gabryś"

    public static let devDev = Acknowledgement(
        id: "devdev", name: "DevDev", url: URL(string: "https://github.com/wojciechgabrys/devdev")!,
        license: "MIT", files: ["devdev-LICENSE.txt"])

    /// The packages, sorted by name.
    public static let packages: [Acknowledgement] = [
        package("eventsource", "EventSource", "https://github.com/mattt/eventsource", "MIT"),
        package("h", "h", "https://github.com/rarestype/h", "Apache-2.0", notice: true),
        package("sparkle", "Sparkle", "https://github.com/sparkle-project/Sparkle", "MIT"),
        package("swift-sdk", "MCP Swift SDK", "https://github.com/modelcontextprotocol/swift-sdk", "MIT and Apache-2.0"),
        package("swift-argument-parser", "Swift Argument Parser", "https://github.com/apple/swift-argument-parser", "Apache-2.0"),
        package("swift-atomics", "Swift Atomics", "https://github.com/apple/swift-atomics", "Apache-2.0"),
        package("swift-collections", "Swift Collections", "https://github.com/apple/swift-collections", "Apache-2.0"),
        package("swift-log", "SwiftLog", "https://github.com/apple/swift-log", "Apache-2.0", notice: true),
        package("swift-nio", "SwiftNIO", "https://github.com/apple/swift-nio", "Apache-2.0", notice: true),
        package("swift-png", "Swift PNG", "https://github.com/tayloraswift/swift-png", "Apache-2.0", notice: true),
        package("swift-system", "Swift System", "https://github.com/apple/swift-system", "Apache-2.0"),
        package("swiftterm", "SwiftTerm", "https://github.com/migueldeicaza/SwiftTerm", "MIT"),
    ].sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// DevDev first, then the packages.
    public static let all: [Acknowledgement] = [devDev] + packages

    /// The full text of an entry's files, read from `bundle`, separated by a blank line.
    /// A missing file reads as a line saying so, so a packaging mistake shows rather than hides.
    public static func text(of entry: Acknowledgement, in bundle: Bundle = .main) -> String {
        entry.files.map { file in
            let name = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            guard let url = bundle.url(forResource: name, withExtension: ext),
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { return "\(file) is missing from this build." }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n\n\n")
    }

    private static func package(
        _ id: String, _ name: String, _ url: String, _ license: String, notice: Bool = false
    ) -> Acknowledgement {
        Acknowledgement(
            id: id, name: name, url: URL(string: url)!, license: license,
            files: ["\(id)-LICENSE.txt"] + (notice ? ["\(id)-NOTICE.txt"] : []))
    }
}
