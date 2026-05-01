import SwiftUI

@main
struct SocialMirrorApp: App {
    @StateObject private var coreData = CoreDataStack.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environment(\.managedObjectContext, coreData.viewContext)
            .environmentObject(coreData)
            .onAppear {
                AudioStorageManager.shared.runAutoDelete()
            }
        }
    }
}
