import Foundation

/// One "Restart when files change" pattern, matched against a path relative to the Project folder.
///
/// `*` matches within one folder, `**` matches any number of folders (including none), `?` matches one
/// character, `{a,b}` matches either part and `[...]` matches one character of the set. Everything
/// else is literal. A leading `/` or `./` means the Project folder itself.
public struct Glob: Sendable, Equatable {
    public let pattern: String
    private let expression: NSRegularExpression?

    public init(_ pattern: String) {
        self.pattern = pattern
        expression = try? NSRegularExpression(pattern: "^" + Self.regex(for: pattern) + "$")
    }

    public func matches(_ relativePath: String) -> Bool {
        guard let expression else { return false }
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        return expression.firstMatch(in: relativePath, range: range) != nil
    }

    public static func == (lhs: Glob, rhs: Glob) -> Bool { lhs.pattern == rhs.pattern }

    /// The path inside the folder, or nil when the path is the folder itself or lies outside it.
    public static func relativePath(_ path: String, inFolder folder: String) -> String? {
        var base = folder
        while base.count > 1, base.hasSuffix("/") { base.removeLast() }
        let prefix = base == "/" ? "/" : base + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = String(path.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
    }

    private static func regex(for pattern: String) -> String {
        var body = Substring(pattern)
        if body.hasPrefix("./") { body = body.dropFirst(2) }
        while body.hasPrefix("/") { body = body.dropFirst() }

        var result = ""
        var braceDepth = 0
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            let next = body.index(after: index)
            switch character {
            case "*":
                if next < body.endIndex, body[next] == "*" {
                    let afterStars = body.index(after: next)
                    if afterStars < body.endIndex, body[afterStars] == "/" {
                        // `**/`: any number of whole folders, including none.
                        result += "(?:.*/)?"
                        index = body.index(after: afterStars)
                    } else {
                        result += ".*"
                        index = afterStars
                    }
                    continue
                }
                result += "[^/]*"
            case "?":
                result += "[^/]"
            case "{":
                braceDepth += 1
                result += "(?:"
            case "}" where braceDepth > 0:
                braceDepth -= 1
                result += ")"
            case "," where braceDepth > 0:
                result += "|"
            case "[":
                if let close = body[next...].firstIndex(of: "]") {
                    var set = String(body[next..<close])
                    if set.hasPrefix("!") { set = "^" + set.dropFirst() }
                    result += "[" + set.replacingOccurrences(of: "\\", with: "\\\\") + "]"
                    index = body.index(after: close)
                    continue
                }
                result += "\\["
            default:
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = next
        }
        result += String(repeating: ")", count: braceDepth)
        return result
    }
}
