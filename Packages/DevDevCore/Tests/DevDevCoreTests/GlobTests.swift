import Foundation
import Testing

@testable import DevDevCore

/// Glob patterns of "Restart when files change", matched against paths relative to the Project folder.
@Suite struct GlobTests {
    private func matches(_ pattern: String, _ path: String) -> Bool {
        Glob(pattern).matches(path)
    }

    @Test func aStarMatchesWithinOneFolderOnly() {
        #expect(matches("*.php", "index.php"))
        #expect(!matches("*.php", "app/index.php"))
        #expect(matches("app/*.php", "app/User.php"))
        #expect(!matches("app/*.php", "app/Models/User.php"))
    }

    @Test func aDoubleStarMatchesAnyDepthIncludingNone() {
        #expect(matches("**/*.php", "index.php"))
        #expect(matches("**/*.php", "app/Models/User.php"))
        #expect(matches("app/**/*.php", "app/User.php"))
        #expect(matches("app/**/*.php", "app/Http/Controllers/Home.php"))
        #expect(!matches("app/**/*.php", "routes/web.php"))
        #expect(matches("config/**", "config/app.php"))
        #expect(matches("config/**", "config/deep/file"))
    }

    @Test func aQuestionMarkBracesAndBracketsWork() {
        #expect(matches("?.txt", "a.txt"))
        #expect(!matches("?.txt", "ab.txt"))
        #expect(matches("**/*.{php,env}", "app/User.php"))
        #expect(matches("**/*.{php,env}", "settings.env"))
        #expect(!matches("**/*.{php,env}", "app/app.js"))
        #expect(matches("file[0-9].log", "file3.log"))
        #expect(!matches("file[0-9].log", "fileA.log"))
    }

    @Test func dotsAndOtherRegexCharactersAreLiteral() {
        #expect(matches(".env", ".env"))
        #expect(!matches(".env", "xenv"))
        #expect(matches("a+b(c).txt", "a+b(c).txt"))
    }

    @Test func aLeadingSlashOrDotSlashMeansTheProjectFolder() {
        #expect(matches("/routes/*.php", "routes/web.php"))
        #expect(matches("./routes/*.php", "routes/web.php"))
    }

    @Test func pathsAreMadeRelativeToTheProjectFolder() {
        #expect(Glob.relativePath("/tmp/p/app/User.php", inFolder: "/tmp/p") == "app/User.php")
        #expect(Glob.relativePath("/tmp/p", inFolder: "/tmp/p") == nil)
        #expect(Glob.relativePath("/tmp/pother/a.php", inFolder: "/tmp/p") == nil)
        #expect(Glob.relativePath("/elsewhere/a.php", inFolder: "/tmp/p") == nil)
        #expect(Glob.relativePath("/tmp/p/a.php", inFolder: "/tmp/p/") == "a.php")
    }
}
