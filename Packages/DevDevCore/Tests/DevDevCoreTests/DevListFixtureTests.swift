import Foundation
import Testing

/// Loads the real `php artisan dev:list` output saved by the spike (see `docs/spike-results.md`).
enum DevListFixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/dev-list"),
            "missing fixture \(name)"
        )
        return try Data(contentsOf: url)
    }
}

private struct ListedProcess: Decodable, Equatable {
    let name: String
    let command: String
}

@Test func defaultDevListFixtureHoldsTheFourDefaultProcesses() throws {
    let listed = try JSONDecoder().decode([ListedProcess].self, from: DevListFixture.data("default.json"))

    #expect(listed == [
        ListedProcess(name: "server", command: "php artisan serve"),
        ListedProcess(name: "queue", command: "php artisan queue:listen --tries=1 --timeout=0"),
        ListedProcess(name: "logs", command: "php artisan pail --timeout=0"),
        ListedProcess(name: "vite", command: "npm run dev"),
    ])
}

@Test func everySavedDevListFixtureIsBundled() throws {
    let names = [
        "default.json", "default-no-interaction.json", "default.txt", "default-ansi.txt", "default-agent-env.txt",
        "custom-registered.json", "custom-registered.txt", "custom-registered-pnpm.json",
        "custom-without-defaults.json", "empty.json", "empty.txt", "filter-no-match.json",
        "command-not-defined.stdout.txt",
    ]
    for name in names {
        #expect(try !DevListFixture.data(name).isEmpty, "fixture \(name) is empty")
    }
}
