import SwiftUI

@main
struct SocialMirrorApp: App {
    @StateObject private var coreData = CoreDataStack.shared
    @State private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isBootstrapping {
                    AuthSplashView()
                } else if authManager.isAuthenticated {
                    NavigationStack {
                        HomeView()
                    }
                    .environment(\.managedObjectContext, coreData.viewContext)
                    .environmentObject(coreData)
                    .onAppear {
                        AudioStorageManager.shared.runAutoDelete()
                    }
                } else {
                    AuthView()
                }
            }
            .task {
                await authManager.bootstrap()
            }
        }
    }
}

/// Minimal launch placeholder shown while a saved session is restored.
private struct AuthSplashView: View {
    var body: some View {
        ZStack {
            Color(hex: "0A0A0A").ignoresSafeArea()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(AppColor.primary)
        }
    }
}
