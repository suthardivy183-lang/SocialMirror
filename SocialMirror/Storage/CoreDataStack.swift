import Combine
import CoreData
import Foundation
import os

final class CoreDataStack: ObservableObject {
    nonisolated static let shared = CoreDataStack()

    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "CoreData")

    nonisolated let objectWillChange = ObservableObjectPublisher()

    nonisolated let container: NSPersistentContainer

    nonisolated var viewContext: NSManagedObjectContext { container.viewContext }

    lazy var backgroundContext: NSManagedObjectContext = {
        let ctx = container.newBackgroundContext()
        ctx.automaticallyMergesChangesFromParent = true
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SocialMirror")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("CoreDataStack: no persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.setOption(
                FileProtectionType.completeUnlessOpen as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                Self.log.error("Failed to load store \(storeDescription.url?.absoluteString ?? "?", privacy: .public): \(error, privacy: .public)")
                fatalError("CoreDataStack load failure: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save(_ context: NSManagedObjectContext? = nil) {
        let ctx = context ?? viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            let nsError = error as NSError
            Self.log.error("Save failed: \(nsError, privacy: .public) — userInfo: \(nsError.userInfo, privacy: .public)")
        }
    }
}
