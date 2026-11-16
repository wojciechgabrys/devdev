import Foundation

/// Matching typed words against Commands, for Go to Command (Cmd-K) and the menubar filter.
///
/// Every word must appear, without regard to case, in the Command's name, its Project's name or its
/// command line. Results keep the window's order, with better matches first.
public enum CommandSearch {
    /// One Command that matched.
    public struct Result: Sendable, Equatable, Identifiable {
        public var id: UUID { commandID }
        public var commandID: UUID
        public var projectID: UUID
        public var commandName: String
        public var projectName: String
        public var commandLine: String
        public var status: CommandStatus
    }

    /// Every Command when the query is empty, otherwise the matching ones, best first.
    public static func results(for query: String, in snapshot: HelperSnapshot) -> [Result] {
        let words = Self.words(query)
        var scored: [(score: Int, order: Int, result: Result)] = []
        for project in snapshot.projects {
            for command in project.commands {
                let fields = Fields(
                    name: command.settings.name, project: project.name, line: command.settings.commandLine)
                guard let score = score(words, fields) else { continue }
                let result = Result(
                    commandID: command.id, projectID: project.id, commandName: command.settings.name,
                    projectName: project.name, commandLine: command.settings.commandLine, status: command.status)
                scored.append((score, scored.count, result))
            }
        }
        return scored.sorted { ($0.score, $0.order) < ($1.score, $1.order) }.map(\.result)
    }

    /// The lowercased words of a query. Empty for a blank query.
    static func words(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    struct Fields {
        var name: String
        var project: String
        var line: String
    }

    /// Lower is better. Nil when a word appears nowhere.
    static func score(_ words: [String], _ fields: Fields) -> Int? {
        let name = fields.name.lowercased()
        let project = fields.project.lowercased()
        let line = fields.line.lowercased()
        var total = 0
        for word in words {
            if name.hasPrefix(word) {
                total += 0
            } else if name.contains(word) {
                total += 1
            } else if project.hasPrefix(word) {
                total += 2
            } else if project.contains(word) {
                total += 3
            } else if line.contains(word) {
                total += 4
            } else {
                return nil
            }
        }
        return total
    }
}
