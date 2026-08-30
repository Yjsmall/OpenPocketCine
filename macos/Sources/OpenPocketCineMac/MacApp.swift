import SwiftUI

@main
struct OpenPocketCineMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("OpenPocketCine") {
            MacRootView()
                .environment(model)
                .environment(\.font, LiveType.text(14))
                .preferredColorScheme(.dark)
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
