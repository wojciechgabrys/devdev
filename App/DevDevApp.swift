import DevDevCore
import SwiftUI

@main
struct DevDevApp: App {
    var body: some Scene {
        WindowGroup("devdev") {
            Text("devdev \(DevDevCore.version)")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
