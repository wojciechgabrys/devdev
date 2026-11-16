import Foundation

/// Turns terminal output into plain text for MCP and other plain-text readers.
public enum PlainText {
    /// Removes escape sequences and control characters, and applies carriage returns.
    public static func strip(_ data: Data) -> String {
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        var lineStart = 0
        let bytes = [UInt8](data)
        var i = 0
        let n = bytes.count

        while i < n {
            let b = bytes[i]
            switch b {
            case 0x1b:
                i = skipEscape(bytes, from: i)
                continue
            case 0x0a:
                out.append(b)
                lineStart = out.count
            case 0x0d:
                // "\r\n" is a line end. A lone "\r" means the line is drawn again from its start.
                if i + 1 < n, bytes[i + 1] == 0x0a { break }
                if i + 1 < n { out.removeSubrange(lineStart...) }
            case 0x08:
                if out.count > lineStart { out.removeLast() }
            case 0x09:
                out.append(b)
            case 0x00...0x1f, 0x7f:
                break
            default:
                out.append(b)
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Returns the index after the escape sequence that starts at `start`.
    private static func skipEscape(_ bytes: [UInt8], from start: Int) -> Int {
        let n = bytes.count
        var i = start + 1
        guard i < n else { return n }
        switch bytes[i] {
        case 0x5b:  // CSI: parameters, then one final byte
            i += 1
            while i < n, !(0x40...0x7e).contains(bytes[i]) { i += 1 }
            return min(i + 1, n)
        case 0x5d, 0x50, 0x5e, 0x5f, 0x58:  // OSC, DCS, PM, APC, SOS: text ended by BEL or ESC \
            i += 1
            while i < n {
                if bytes[i] == 0x07 { return i + 1 }
                if bytes[i] == 0x1b, i + 1 < n, bytes[i + 1] == 0x5c { return i + 2 }
                i += 1
            }
            return n
        default:  // optional intermediate bytes, then one final byte
            while i < n, (0x20...0x2f).contains(bytes[i]) { i += 1 }
            return min(i + 1, n)
        }
    }
}
