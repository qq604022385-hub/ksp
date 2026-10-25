import SwiftUI

@main
@MainActor
struct KankeApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var library = LibraryStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environmentObject(library)
                .tint(Color(red: 0.60, green: 0.66, blue: 1))
                .preferredColorScheme(.dark)
        }
    }
}
