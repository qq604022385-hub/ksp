import SwiftUI
import UIKit
import KSPlayer

final class KankeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        KSOptions.supportedInterfaceOrientations
    }
}

@main
@MainActor
struct KankeApp: App {
    @UIApplicationDelegateAdaptor(KankeAppDelegate.self) private var appDelegate
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
