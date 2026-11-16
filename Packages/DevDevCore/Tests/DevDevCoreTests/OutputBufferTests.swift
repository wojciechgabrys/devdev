import Foundation
import Testing

@testable import DevDevCore

@Suite struct OutputBufferTests {
    @Test func bufferKeepsAtMostTenThousandLines() {
        var buffer = OutputBuffer()
        #expect(buffer.maxLines == 10_000)
        for number in 1...10_050 {
            buffer.append(Data("line \(number)\n".utf8))
        }
        #expect(buffer.lineCount == 10_000)
        let text = buffer.plainText()
        #expect(text.hasPrefix("line 51\n"))
        #expect(text.hasSuffix("line 10050\n"))
    }

    @Test func bufferStaysUnderItsByteCapForOneEndlessLine() {
        var buffer = OutputBuffer()
        let chunk = Data(repeating: UInt8(ascii: "x"), count: 1024 * 1024)
        for _ in 0..<20 {
            buffer.append(chunk)
        }
        buffer.append(Data("END".utf8))
        #expect(buffer.bytes <= buffer.maxBytes)
        #expect(buffer.data.count <= OutputBuffer.standardMaxBytes)
        #expect(buffer.lineCount == 1)
        #expect(buffer.data.suffix(3) == Data("END".utf8))
    }

    @Test func byteCapDropsOldLinesFirst() {
        var buffer = OutputBuffer(maxLines: 100, maxBytes: 10)
        buffer.append(Data("aaaa\nbbbb\ncccc\n".utf8))
        #expect(buffer.plainText() == "bbbb\ncccc\n")
    }

    @Test func chunksThatSplitALineAreJoined() {
        var buffer = OutputBuffer()
        buffer.append(Data("hel".utf8))
        #expect(buffer.endsMidLine)
        buffer.append(Data("lo\nwor".utf8))
        buffer.append(Data("ld\n".utf8))
        #expect(buffer.lineCount == 2)
        #expect(!buffer.endsMidLine)
        #expect(buffer.data == Data("hello\nworld\n".utf8))
    }

    @Test func plainTextCanBeLimitedToTheLastLines() {
        var buffer = OutputBuffer()
        buffer.append(Data("one\r\ntwo\r\nthree\r\n".utf8))
        #expect(buffer.plainText(lastLines: 2) == "two\nthree")
        #expect(buffer.plainText(lastLines: 10) == "one\ntwo\nthree")
    }

    @Test func plainTextRemovesEscapeSequences() {
        let raw = "\u{1b}[32mgreen\u{1b}[0m \u{1b}]0;window title\u{07}plain\u{1b}(B\r\n\u{1b}[2K\u{1b}[1Gnext\r\n"
        #expect(PlainText.strip(Data(raw.utf8)) == "green plain\nnext\n")
    }

    @Test func plainTextAppliesCarriageReturnRedraws() {
        #expect(PlainText.strip(Data("10%\r50%\r100%\r\ndone\r\n".utf8)) == "100%\ndone\n")
    }

    @Test func bannerLineIsVisibleInPlainTextAndStartsOnItsOwnLine() {
        var buffer = OutputBuffer()
        buffer.append(Data("partial".utf8))
        buffer.append(OutputBanner.line(OutputBanner.ended(.exited(1)), afterPartialLine: buffer.endsMidLine))
        #expect(buffer.plainText() == "partial\n── exited with code 1 ──\n")
    }

    @Test func restartBannerShowsTheClockTime() throws {
        let date = Date(timeIntervalSince1970: 14 * 3600 + 2 * 60 + 11)
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(OutputBanner.restarted(at: date, timeZone: utc) == "restarted 14:02:11")
    }
}
