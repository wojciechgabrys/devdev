// Checks that a disk image's EdDSA signature, as the appcast carries it, verifies against the
// public key inside a built app. Sparkle makes the same check before it installs an update, so a
// release that fails here could never be installed by the copies of the app already out there.
//
// Usage: swift scripts/verify-update-signature.swift <dmg> <appcast.xml> <devdev.app>
//
//   <dmg>          The disk image the release will hold.
//   <appcast.xml>  The appcast made for it. The signature is read from its enclosure.
//   <devdev.app>   The built app. The public key is SUPublicEDKey in its Info.plist.
//
// Only public values are read: no private key, no Keychain. Sparkle's sign_update --verify needs
// the private key, so it cannot make this check.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Finds the `sparkle:edSignature` of each enclosure. Text inside the notes is never an attribute.
final class Enclosures: NSObject, XMLParserDelegate {
    var signatures: [String?] = []

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        if name == "enclosure" { signatures.append(attributes["sparkle:edSignature"]) }
    }
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: swift scripts/verify-update-signature.swift <dmg> <appcast.xml> <devdev.app>\n".utf8))
    exit(64)
}
let diskPath = arguments[arguments.startIndex]
let appcastPath = arguments[arguments.startIndex + 1]
let appPath = arguments[arguments.startIndex + 2]

// The public key in the app.
let infoPath = appPath + "/Contents/Info.plist"
guard let infoData = FileManager.default.contents(atPath: infoPath),
    let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
else {
    fail("\(infoPath) could not be read.")
}
guard let keyText = info["SUPublicEDKey"] as? String else {
    fail("\(infoPath) has no SUPublicEDKey.")
}
guard let keyBytes = Data(base64Encoded: keyText), keyBytes.count == 32,
    let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
else {
    fail("SUPublicEDKey in \(infoPath) is not the base64 of a 32-byte key.")
}

// The signature in the appcast.
guard let appcastData = FileManager.default.contents(atPath: appcastPath) else {
    fail("\(appcastPath) could not be read.")
}
let enclosures = Enclosures()
let parser = XMLParser(data: appcastData)
parser.delegate = enclosures
guard parser.parse() else {
    fail("\(appcastPath) is not well-formed XML.")
}
guard enclosures.signatures.count == 1 else {
    fail("\(appcastPath) must hold one enclosure. It holds \(enclosures.signatures.count).")
}
guard let signatureText = enclosures.signatures[0], let signature = Data(base64Encoded: signatureText),
    signature.count == 64
else {
    fail("The enclosure in \(appcastPath) has no EdDSA signature.")
}

// The disk image.
guard let disk = FileManager.default.contents(atPath: diskPath) else {
    fail("\(diskPath) could not be read.")
}

guard key.isValidSignature(signature, for: disk) else {
    fail(
        "The signature of \(diskPath) does not verify against the SUPublicEDKey in \(infoPath). "
            + "The private key that signed it is not the pair of the public key the app ships.")
}
print("The signature of \(diskPath) verifies against the SUPublicEDKey in the app.")
