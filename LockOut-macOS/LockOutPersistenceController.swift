import LockOutCore
import SwiftData

enum LockOutSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [BreakSessionRecord.self] }
}

enum LockOutSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LockOutSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum LockOutPersistenceController {
    static func makeContainer(isUITesting: Bool) throws -> ModelContainer {
        let config = isUITesting ? ModelConfiguration(isStoredInMemoryOnly: true) : ModelConfiguration()
        return try ModelContainer(
            for: BreakSessionRecord.self,
            migrationPlan: LockOutSchemaMigrationPlan.self,
            configurations: config
        )
    }
}
