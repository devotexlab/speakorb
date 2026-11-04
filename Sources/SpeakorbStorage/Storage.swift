import Foundation
import Security
import SQLite3
import SpeakorbCore

public enum StorageModule {
    public static let moduleName = "SpeakorbStorage"
}

// MARK: - Keychain

/// SecItem 的可注入薄封装：生产走系统钥匙串，测试用内存替身，
/// 这样钥匙串逻辑（更新/新增/删除幂等/错误映射）在无 GUI 会话的 CI 里也能测。
public protocol KeychainAccessing {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

public struct SystemKeychainAccess: KeychainAccessing {
    public init() {}

    public func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw SpeakorbError.keychainFailed("SecItemCopyMatching OSStatus \(status)")
        }
    }

    public func write(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SpeakorbError.keychainFailed("SecItemUpdate OSStatus \(updateStatus)")
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SpeakorbError.keychainFailed("SecItemAdd OSStatus \(addStatus)")
        }
    }

    public func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SpeakorbError.keychainFailed("SecItemDelete OSStatus \(status)")
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// API key 存储：只写 macOS 钥匙串，绝不落 UserDefaults / 文件 / 日志。
/// 服务名固定为 app.speakorb.keys，account 为 ProviderID.rawValue。
public final class KeychainKeyStore: KeyStoring {
    public static let defaultService = "app.speakorb.keys"

    private let service: String
    private let access: KeychainAccessing

    public init(service: String = KeychainKeyStore.defaultService,
                access: KeychainAccessing = SystemKeychainAccess()) {
        self.service = service
        self.access = access
    }

    public func setKey(_ key: String, for provider: ProviderID) throws {
        guard let data = key.data(using: .utf8) else {
            throw SpeakorbError.keychainFailed("key is not valid UTF-8")
        }
        try mapKeychainError {
            try access.write(data, service: service, account: provider.rawValue)
        }
    }

    public func key(for provider: ProviderID) -> String? {
        // 读不到（含 not found / 钥匙串不可用）统一返回 nil，不把 OSStatus 抛给 UI。
        // Swift 5 的 try? 会压平 Optional：not found 与读取错误都落到 nil。
        guard let data = try? access.read(service: service, account: provider.rawValue) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func removeKey(for provider: ProviderID) throws {
        try mapKeychainError {
            try access.delete(service: service, account: provider.rawValue)
        }
    }

    private func mapKeychainError<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as SpeakorbError {
            if case .keychainFailed = error { throw error }
            throw SpeakorbError.keychainFailed("\(error.code): \(String(describing: error))")
        } catch {
            throw SpeakorbError.keychainFailed(String(describing: error))
        }
    }
}

// MARK: - SQLite history

/// 本地听写历史：SQLite3 C API，WAL 模式，单库单写者（内部串行化）。
/// 时间以 Unix epoch 秒（REAL）存储，避免时区/格式问题。
public final class SQLiteHistoryStore: HistoryStoring {
    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openStatus = sqlite3_open_v2(path, &handle, flags, nil)
        guard openStatus == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle = handle { sqlite3_close(handle) }
            throw SpeakorbError.storageFailed("sqlite open failed: \(message)")
        }
        db = opened
        do {
            try configure()
            try createSchemaIfNeeded()
        } catch {
            sqlite3_close(opened)
            db = nil
            throw error
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    public func save(_ record: TranscriptRecord) throws {
        try withDatabase { db in
            let sql = """
            INSERT OR REPLACE INTO transcripts
                (id, text, created_at, provider, route, duration_ms, latency_ms)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql, in: db)
            defer { sqlite3_finalize(statement) }
            try bindText(record.id.uuidString, at: 1, in: statement, db: db)
            try bindText(record.text, at: 2, in: statement, db: db)
            guard sqlite3_bind_double(statement, 3, record.createdAt.timeIntervalSince1970) == SQLITE_OK else {
                throw storageError(db, "bind created_at")
            }
            try bindText(record.provider.rawValue, at: 4, in: statement, db: db)
            try bindText(record.route.rawValue, at: 5, in: statement, db: db)
            guard sqlite3_bind_int64(statement, 6, Int64(record.durationMs)) == SQLITE_OK else {
                throw storageError(db, "bind duration_ms")
            }
            guard sqlite3_bind_int64(statement, 7, Int64(record.latencyMs)) == SQLITE_OK else {
                throw storageError(db, "bind latency_ms")
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw storageError(db, "insert")
            }
        }
    }

    public func recent(limit: Int) throws -> [TranscriptRecord] {
        guard limit > 0 else { return [] }
        return try withDatabase { db in
            let sql = """
            SELECT id, text, created_at, provider, route, duration_ms, latency_ms
            FROM transcripts
            ORDER BY created_at DESC, rowid DESC
            LIMIT ?;
            """
            let statement = try prepare(sql, in: db)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_int64(statement, 1, Int64(limit)) == SQLITE_OK else {
                throw storageError(db, "bind limit")
            }
            var records: [TranscriptRecord] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw storageError(db, "select") }
                guard
                    let idString = columnText(statement, 0),
                    let id = UUID(uuidString: idString),
                    let text = columnText(statement, 1),
                    let providerString = columnText(statement, 3),
                    let provider = ProviderID(rawValue: providerString),
                    let routeString = columnText(statement, 4),
                    let route = Route(rawValue: routeString)
                else {
                    // 损坏行跳过，不影响其余历史可读。
                    continue
                }
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                let durationMs = Int(sqlite3_column_int64(statement, 5))
                let latencyMs = Int(sqlite3_column_int64(statement, 6))
                records.append(TranscriptRecord(
                    id: id,
                    text: text,
                    createdAt: createdAt,
                    provider: provider,
                    route: route,
                    durationMs: durationMs,
                    latencyMs: latencyMs
                ))
            }
            return records
        }
    }

    public func delete(id: UUID) throws {
        try withDatabase { db in
            let statement = try prepare("DELETE FROM transcripts WHERE id = ?;", in: db)
            defer { sqlite3_finalize(statement) }
            try bindText(id.uuidString, at: 1, in: statement, db: db)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw storageError(db, "delete")
            }
        }
    }

    public func clear() throws {
        try withDatabase { db in
            let statement = try prepare("DELETE FROM transcripts;", in: db)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw storageError(db, "clear")
            }
        }
    }

    // MARK: helpers

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else {
            throw SpeakorbError.storageFailed("database is closed")
        }
        return try body(db)
    }

    private func configure() throws {
        guard let db = db else { throw SpeakorbError.storageFailed("database is closed") }
        try execute("PRAGMA journal_mode = WAL;", in: db)
        try execute("PRAGMA synchronous = NORMAL;", in: db)
        try execute("PRAGMA busy_timeout = 5000;", in: db)
    }

    private func createSchemaIfNeeded() throws {
        guard let db = db else { throw SpeakorbError.storageFailed("database is closed") }
        try execute("""
        CREATE TABLE IF NOT EXISTS transcripts (
            id TEXT PRIMARY KEY NOT NULL,
            text TEXT NOT NULL,
            created_at REAL NOT NULL,
            provider TEXT NOT NULL,
            route TEXT NOT NULL,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            latency_ms INTEGER NOT NULL DEFAULT 0
        );
        """, in: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_transcripts_created_at ON transcripts(created_at DESC);", in: db)
    }

    private func execute(_ sql: String, in db: OpaquePointer) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw storageError(db, "exec")
        }
    }

    private func prepare(_ sql: String, in db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            throw storageError(db, "prepare")
        }
        return prepared
    }

    private func bindText(_ value: String, at index: Int32, in statement: OpaquePointer, db: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw storageError(db, "bind text")
        }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func storageError(_ db: OpaquePointer, _ operation: String) -> SpeakorbError {
        .storageFailed("\(operation): \(String(cString: sqlite3_errmsg(db)))")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Settings

/// 设置存储：JSONEncoder 编码 AppSettings 后写入 UserDefaults；支持注入 suite 便于测试。
public final class UserDefaultsSettingsStore: SettingsStoring {
    public static let defaultStorageKey = "speakorb.settings.v1"

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private var cached: AppSettings

    public init(defaults: UserDefaults = .standard, storageKey: String = UserDefaultsSettingsStore.defaultStorageKey) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.cached = Self.decodeSettings(from: defaults, key: storageKey) ?? AppSettings()
    }

    public convenience init(suiteName: String, storageKey: String = UserDefaultsSettingsStore.defaultStorageKey) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.init(defaults: defaults, storageKey: storageKey)
    }

    public var settings: AppSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return cached
        }
        set {
            lock.lock()
            cached = newValue
            persist(newValue)
            lock.unlock()
        }
    }

    public func save() {
        lock.lock()
        defer { lock.unlock() }
        persist(cached)
    }

    // MARK: helpers

    private func persist(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func decodeSettings(from defaults: UserDefaults, key: String) -> AppSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
