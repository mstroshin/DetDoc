import SwiftUI

@main
struct DetDocAppMain: App {
    @State private var coordinator = AppCoordinator(picker: SystemFolderPicker())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}
