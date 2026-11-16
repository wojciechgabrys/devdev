import Testing

@testable import DevDevCore

@Test func versionIsSet() {
    #expect(!DevDevCore.version.isEmpty)
}
