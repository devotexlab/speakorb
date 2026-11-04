import Foundation
import SpeakorbCore
import SpeakorbStorage

/// 内部代号 Talktype 时期的数据搬到 Speakorb：说过的话、设置、接入的钥匙。
/// 只在第一次启动新版本时跑一次；新位置已有数据就不覆盖。旧数据原样保留，不删除。
enum LegacyMigration {
    private static let doneKey = "speakorb.migratedFromTalktype"
    /// 打包版用 com.talktype.app；`swift run` 的开发版用可执行文件名。
    private static let oldDefaultsDomains = ["com.talktype.app", "Talktype"]
    private static let oldSettingsKey = "talktype.settings.v1"
    private static let oldOnboardedKey = "talktype.onboarded"
    private static let oldKeychainService = "com.talktype.keys"

    static func runIfNeeded(supportDirectory: URL, newDirectory: URL, newDatabaseName: String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        copyHistory(from: supportDirectory.appendingPathComponent("Talktype", isDirectory: true),
                    to: newDirectory, databaseName: newDatabaseName)
        copyDefaults(into: defaults)
        copyKeys()
    }

    private static func copyHistory(from oldDirectory: URL, to newDirectory: URL, databaseName: String) {
        let fm = FileManager.default
        let newDB = newDirectory.appendingPathComponent(databaseName)
        guard !fm.fileExists(atPath: newDB.path) else { return }
        // SQLite 用了 WAL，三个文件要一起搬。
        for suffix in ["", "-wal", "-shm"] {
            let old = oldDirectory.appendingPathComponent("talktype.sqlite" + suffix)
            guard fm.fileExists(atPath: old.path) else { continue }
            try? fm.copyItem(at: old, to: newDirectory.appendingPathComponent(databaseName + suffix))
        }
    }

    private static func copyDefaults(into defaults: UserDefaults) {
        for domain in oldDefaultsDomains {
            guard let old = UserDefaults(suiteName: domain) else { continue }
            if defaults.data(forKey: UserDefaultsSettingsStore.defaultStorageKey) == nil,
               let settings = old.data(forKey: oldSettingsKey) {
                defaults.set(settings, forKey: UserDefaultsSettingsStore.defaultStorageKey)
            }
            if defaults.object(forKey: "speakorb.onboarded") == nil, old.bool(forKey: oldOnboardedKey) {
                defaults.set(true, forKey: "speakorb.onboarded")
            }
        }
    }

    private static func copyKeys() {
        let oldStore = KeychainKeyStore(service: oldKeychainService)
        let newStore = KeychainKeyStore()
        for provider in ProviderID.allCases where provider != .local {
            guard newStore.key(for: provider) == nil, let key = oldStore.key(for: provider) else { continue }
            try? newStore.setKey(key, for: provider)
        }
    }
}
