import Foundation
import SwiftUI
import SpeakorbCore
import SpeakorbCapture
import SpeakorbStorage
import SpeakorbProviders

/// 依赖装配点：模块完成后只改这里。
struct AppDependencies {
    var audio: AudioCapturing
    var local: LocalTranscribing
    var providers: ProviderResolving
    var injector: Injecting
    var keys: KeyStoring
    var history: HistoryStoring
    var settings: SettingsStoring
    var permissions: PermissionChecking
    var hotkey: HotkeyMonitoring

    static func live() -> AppDependencies {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("Speakorb", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbName = "speakorb.sqlite"
        LegacyMigration.runIfNeeded(supportDirectory: support, newDirectory: dir, newDatabaseName: dbName)
        let dbURL = dir.appendingPathComponent(dbName)

        let history: HistoryStoring
        if let store = try? SQLiteHistoryStore(path: dbURL.path) {
            history = store
        } else {
            history = InMemoryHistoryStore()
        }

        let keyStore = KeychainKeyStore()
        let settingsStore = UserDefaultsSettingsStore()

        return AppDependencies(
            audio: AudioRecorder(maxDurationSeconds: 180),
            local: SpeechTranscriber(),
            providers: LiveProviderResolver(keys: keyStore, settings: settingsStore),
            injector: Paster(),
            keys: keyStore,
            history: history,
            settings: settingsStore,
            permissions: Permissions(),
            hotkey: HotkeyMonitor()
        )
    }
}


/// 运行时按当前钥匙串里的 key 解析供应商（用户随时可接入/更换）。
final class LiveProviderResolver: ProviderResolving {
    private let keys: KeyStoring
    private let settings: SettingsStoring
    private let transport = URLSessionTransport()

    init(keys: KeyStoring, settings: SettingsStoring) {
        self.keys = keys
        self.settings = settings
    }

    func provider(for id: ProviderID) -> CloudCompleting? {
        guard let key = keys.key(for: id), !key.isEmpty else { return nil }
        var custom: CustomProviderSettings?
        if id == .custom {
            let current = settings.settings
            guard
                let url = URL(string: current.customBaseURL),
                !current.customBaseURL.isEmpty,
                !current.customModel.isEmpty
            else { return nil }
            custom = CustomProviderSettings(baseURL: url, model: current.customModel)
        }
        let registry = ProviderFactory.standard(keys: [id: key], custom: custom, transport: transport)
        return registry.provider(for: id)
    }
}

// 仅保留内存历史作为 SQLite 不可用时的兜底。

final class InMemoryHistoryStore: HistoryStoring {
    private var records: [TranscriptRecord] = []
    func save(_ record: TranscriptRecord) throws { records.insert(record, at: 0) }
    func recent(limit: Int) throws -> [TranscriptRecord] { Array(records.prefix(limit)) }
    func delete(id: UUID) throws { records.removeAll { $0.id == id } }
    func clear() throws { records.removeAll() }
}
