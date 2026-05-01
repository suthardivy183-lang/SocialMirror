//
//  SocialMirrorApp.swift
//  SocialMirror
//
//  Created by SUTHAR DIVY DEVENDRABHAI on 01/05/26.
//

import SwiftUI
import CoreData

@main
struct SocialMirrorApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
