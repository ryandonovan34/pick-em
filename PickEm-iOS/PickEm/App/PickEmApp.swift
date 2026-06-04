import SwiftUI

@main
struct PickEmApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .tint(AdaptiveColor.pePrimaryFill)
        }
    }
}
