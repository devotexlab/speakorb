import XCTest
@testable import SpeakorbStorage
import SpeakorbCore

final class StorageSmokeTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(StorageModule.moduleName.isEmpty)
    }
}

// MARK: - Keychain

final class KeychainKeyStoreTests: XCTestCase {
    private var store: KeychainKeyStore!

    override func setUp() {
        super.setUp()
        store = KeychainKeyStore()
    }

    override func tearDown() {
        try? store.removeKey(for: .custom)
        try? store.removeKey(for: .gemini)
        super.tearDown()
    }

    /// 钥匙串在无登录会话/受限沙箱里可能不可用：此时跳过而不是误报失败。
    private func requireKeychain() throws {
        do {
            try store.setKey("probe", for: .custom)
            try store.removeKey(for: .custom)
        } catch {
            throw XCTSkip("keychain unavailable in this environment: \(error)")
        }
    }

    func testSetGetOverwriteAndRemove() throws {
        try requireKeychain()
        try store.removeKey(for: .custom)
        XCTAssertNil(store.key(for: .custom))

        try store.setKey("key-one", for: .custom)
        XCTAssertEqual(store.key(for: .custom), "key-one")

        try store.setKey("key-two", for: .custom)
        XCTAssertEqual(store.key(for: .custom), "key-two")

        try store.removeKey(for: .custom)
        XCTAssertNil(store.key(for: .custom))
    }

    func testRemoveIsIdempotent() throws {
        try requireKeychain()
        try store.setKey("temporary", for: .custom)
        try store.removeKey(for: .custom)
        XCTAssertNoThrow(try store.removeKey(for: .custom))
        XCTAssertNil(store.key(for: .custom))
    }

    func testProvidersAreIsolated() throws {
        try requireKeychain()
        try store.setKey("gemini-key", for: .gemini)
        try store.setKey("custom-key", for: .custom)
        XCTAssertEqual(store.key(for: .gemini), "gemini-key")
        XCTAssertEqual(store.key(for: .custom), "custom-key")
        try store.removeKey(for: .gemini)
        XCTAssertNil(store.key(for: .gemini))
        XCTAssertEqual(store.key(for: .custom), "custom-key")
    }
}

// MARK: - SQLite history

final class SQLiteHistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var databasePath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakorbStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        databasePath = directory.appendingPathComponent("history.sqlite").path
    }

    override func tearDownWithError() throws {
        if let directory = directory {
            try? FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    private func makeRecord(
        text: String,
        createdAt: Date,
        provider: ProviderID = .gemini,
        route: Route = .cloudDirect
    ) -> TranscriptRecord {
        TranscriptRecord(
            text: text,
            createdAt: createdAt,
            provider: provider,
            route: route,
            durationMs: 1_800,
            latencyMs: 2_200
        )
    }

    func testSaveAndRecentOrdersNewestFirst() throws {
        let store = try SQLiteHistoryStore(path: databasePath)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let first = makeRecord(text: "第一句", createdAt: base)
        let second = makeRecord(text: "第二句", createdAt: base.addingTimeInterval(60))
        let third = makeRecord(text: "第三句", createdAt: base.addingTimeInterval(120))
        try store.save(first)
        try store.save(second)
        try store.save(third)

        let all = try store.recent(limit: 10)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.map(\.text), ["第三句", "第二句", "第一句"])
        XCTAssertEqual(all[0].provider, .gemini)
        XCTAssertEqual(all[0].route, .cloudDirect)
        XCTAssertEqual(all[0].durationMs, 1_800)
        XCTAssertEqual(all[0].latencyMs, 2_200)

        let topTwo = try store.recent(limit: 2)
        XCTAssertEqual(topTwo.count, 2)
        XCTAssertEqual(topTwo.map(\.text), ["第三句", "第二句"])
    }

    func testRecentWithNonPositiveLimitReturnsEmpty() throws {
        let store = try SQLiteHistoryStore(path: databasePath)
        try store.save(makeRecord(text: "只有一句", createdAt: Date()))
        XCTAssertTrue(try store.recent(limit: 0).isEmpty)
        XCTAssertTrue(try store.recent(limit: -5).isEmpty)
    }

    func testDeleteRemovesOnlyTargetRecord() throws {
        let store = try SQLiteHistoryStore(path: databasePath)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let keep = makeRecord(text: "保留", createdAt: base)
        let remove = makeRecord(text: "删除", createdAt: base.addingTimeInterval(1))
        try store.save(keep)
        try store.save(remove)

        try store.delete(id: remove.id)
        let records = try store.recent(limit: 10)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, keep.id)
    }

    func testClearRemovesAllRecords() throws {
        let store = try SQLiteHistoryStore(path: databasePath)
        try store.save(makeRecord(text: "一", createdAt: Date()))
        try store.save(makeRecord(text: "二", createdAt: Date().addingTimeInterval(1)))
        try store.clear()
        XCTAssertTrue(try store.recent(limit: 10).isEmpty)
    }

    func testPersistenceAcrossReopenAndTimestampRoundTrip() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000.25)
        do {
            let store = try SQLiteHistoryStore(path: databasePath)
            try store.save(makeRecord(text: "重新打开还在", createdAt: base, provider: .local, route: .local))
        }
        let reopened = try SQLiteHistoryStore(path: databasePath)
        let records = try reopened.recent(limit: 10)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].text, "重新打开还在")
        XCTAssertEqual(records[0].provider, .local)
        XCTAssertEqual(records[0].route, .local)
        XCTAssertEqual(records[0].createdAt.timeIntervalSince1970, base.timeIntervalSince1970, accuracy: 0.001)
    }

    func testSaveSameRecordTwiceReplacesInsteadOfDuplicating() throws {
        let store = try SQLiteHistoryStore(path: databasePath)
        var record = makeRecord(text: "原始", createdAt: Date())
        try store.save(record)
        record.text = "修改后"
        try store.save(record)
        let records = try store.recent(limit: 10)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].text, "修改后")
    }

    func testOpeningDirectoryPathFailsWithStorageError() throws {
        let directoryPath = directory.path
        XCTAssertThrowsError(try SQLiteHistoryStore(path: directoryPath)) { error in
            guard case SpeakorbError.storageFailed = error else {
                return XCTFail("expected storageFailed, got \(error)")
            }
        }
    }
}

// MARK: - Settings

final class UserDefaultsSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SpeakorbStorageTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsWhenNothingStored() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, AppSettings())
    }

    func testSaveAndReloadFromSameDefaults() throws {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = store.settings
        settings.language = "en-US"
        settings.hotkey = "controlSpace"
        settings.allowCloud = false
        settings.maxRecordingSeconds = 90
        store.settings = settings
        store.save()

        let reloaded = UserDefaultsSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings, settings)
    }

    func testStoredValueIsJSONEncodedSettings() throws {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = store.settings
        settings.preferredProvider = .gemini
        store.settings = settings

        let data = try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsStore.defaultStorageKey))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testSuiteNameConvenienceInitializerRoundTrips() throws {
        let first = UserDefaultsSettingsStore(suiteName: suiteName)
        var settings = first.settings
        settings.launchAtLogin = true
        first.settings = settings
        first.save()

        let second = UserDefaultsSettingsStore(suiteName: suiteName)
        XCTAssertTrue(second.settings.launchAtLogin)
    }

    func testCorruptedStoredDataFallsBackToDefaults() throws {
        defaults.set(Data("not-json".utf8), forKey: UserDefaultsSettingsStore.defaultStorageKey)
        let store = UserDefaultsSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, AppSettings())
    }
}


// MARK: - Keychain logic (runs even when the system keychain is unavailable)

private final class FakeKeychainAccess: KeychainAccessing {
    var storage: [String: Data] = [:]
    var writeError: Error?
    var readError: Error?
    var deleteError: Error?
    private(set) var lastService: String?
    private(set) var lastAccount: String?

    private func key(service: String, account: String) -> String {
        service + "|" + account
    }

    func read(service: String, account: String) throws -> Data? {
        lastService = service
        lastAccount = account
        if let readError = readError { throw readError }
        return storage[key(service: service, account: account)]
    }

    func write(_ data: Data, service: String, account: String) throws {
        lastService = service
        lastAccount = account
        if let writeError = writeError { throw writeError }
        storage[key(service: service, account: account)] = data
    }

    func delete(service: String, account: String) throws {
        lastService = service
        lastAccount = account
        if let deleteError = deleteError { throw deleteError }
        storage.removeValue(forKey: key(service: service, account: account))
    }
}

final class KeychainKeyStoreLogicTests: XCTestCase {
    private func makeStore() -> (KeychainKeyStore, FakeKeychainAccess) {
        let fake = FakeKeychainAccess()
        let store = KeychainKeyStore(service: "app.speakorb.keys", access: fake)
        return (store, fake)
    }

    func testConstantServiceName() {
        XCTAssertEqual(KeychainKeyStore.defaultService, "app.speakorb.keys")
    }

    func testSetUsesServiceAndProviderAccount() throws {
        let (store, fake) = makeStore()
        try store.setKey("secret", for: .deepseek)
        XCTAssertEqual(fake.lastService, "app.speakorb.keys")
        XCTAssertEqual(fake.lastAccount, ProviderID.deepseek.rawValue)
    }

    func testSetGetOverwriteRemove() throws {
        let (store, _) = makeStore()
        XCTAssertNil(store.key(for: .gemini))
        try store.setKey("k1", for: .gemini)
        XCTAssertEqual(store.key(for: .gemini), "k1")
        try store.setKey("k2", for: .gemini)
        XCTAssertEqual(store.key(for: .gemini), "k2")
        try store.removeKey(for: .gemini)
        XCTAssertNil(store.key(for: .gemini))
    }

    func testRemoveIsIdempotent() throws {
        let (store, _) = makeStore()
        try store.removeKey(for: .openai)
        XCTAssertNoThrow(try store.removeKey(for: .openai))
    }

    func testKeysAreIsolatedPerProvider() throws {
        let (store, fake) = makeStore()
        try store.setKey("gemini", for: .gemini)
        try store.setKey("openai", for: .openai)
        XCTAssertEqual(store.key(for: .gemini), "gemini")
        XCTAssertEqual(store.key(for: .openai), "openai")
        XCTAssertEqual(fake.storage.count, 2)
    }

    func testWriteFailureMapsToKeychainFailed() {
        let (store, fake) = makeStore()
        fake.writeError = SpeakorbError.storageFailed("boom")
        XCTAssertThrowsError(try store.setKey("k", for: .custom)) { error in
            guard case SpeakorbError.keychainFailed = error else {
                return XCTFail("expected keychainFailed, got \(error)")
            }
        }
    }

    func testDeleteFailureMapsToKeychainFailed() {
        let (store, fake) = makeStore()
        fake.deleteError = SpeakorbError.storageFailed("boom")
        XCTAssertThrowsError(try store.removeKey(for: .custom)) { error in
            guard case SpeakorbError.keychainFailed = error else {
                return XCTFail("expected keychainFailed, got \(error)")
            }
        }
    }

    func testReadFailureReturnsNilInsteadOfThrowing() {
        let (store, fake) = makeStore()
        fake.readError = SpeakorbError.keychainFailed("unavailable")
        XCTAssertNil(store.key(for: .custom))
    }
}
