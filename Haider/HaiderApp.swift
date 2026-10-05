import SwiftUI

@main
struct HaiderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}