import Foundation
import CryptoKit

/// Valore JSON confrontabile (impostazioni sincronizzate con l'account BCW).
nonisolated enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var number: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }
}

/// Sincronizzazione con l'account BCW, come `CloudSync` di `js/cloud.js` nella versione web.
///
/// Impostazioni e orario sono documenti con una versione: chi salva invia la versione da cui è
/// partito e, se nel frattempo un altro dispositivo ha salvato, riceve il documento attuale e
/// unisce le modifiche. Le impostazioni si uniscono chiave per chiave (vincono quelle cambiate
/// qui); l'orario è un documento unico (vince il lato cambiato, se sono cambiati entrambi questo
/// dispositivo; la prima volta il server). I file allegati si caricano prima dell'orario che li cita.
@Observable
final class CloudSync {
    enum Status: Equatable { case idle, syncing, ok, offline, failed }

    private(set) var status: Status = .idle
    private(set) var message: String?
    private(set) var lastSync: Date?
    /// File non caricato (spazio esaurito, file troppo grande): l'orario si sincronizza lo stesso.
    private(set) var fileWarning: String?

    @ObservationIgnored weak var model: AppModel?

    private struct TimetableState: Codable {
        var version: Int
        var hash: String?
    }

    private struct SyncState: Codable {
        var settingsVersion = 0
        /// Impostazioni all'ultima sincronizzazione (`nil` = mai sincronizzate qui).
        var settingsSnapshot: [String: JSONValue]?
        /// Ultimo documento del server, con le chiavi che questa versione non conosce.
        var settingsRemote: [String: JSONValue]?
        var timetables: [String: TimetableState] = [:]
    }

    private static let stateKey = "bcwSyncState"
    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var waiting: [String: () async throws -> Void] = [:]
    @ObservationIgnored private var running = 0
    @ObservationIgnored private var isApplying = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.stateKey),
           let saved = try? JSONDecoder().decode(SyncState.self, from: data) {
            state = saved
        } else {
            state = SyncState()
        }
    }

    private var token: String? { model?.cloud?.token }
    var isEnabled: Bool { token != nil }

    private func saveState() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    /// Dimentica tutto (uscita dall'account BCW).
    func reset() {
        for timer in timers.values { timer.cancel() }
        timers = [:]
        waiting = [:]
        state = SyncState()
        status = .idle
        message = nil
        lastSync = nil
        fileWarning = nil
        UserDefaults.standard.removeObject(forKey: Self.stateKey)
    }

    // MARK: Coda delle operazioni

    /// Le operazioni vanno una dopo l'altra; lo stato mostrato nelle impostazioni le segue.
    @discardableResult
    private func enqueue(_ operation: @escaping () async throws -> Void) -> Task<Void, Never> {
        let previous = queue
        let task = Task { [weak self] in
            await previous?.value
            await self?.perform(operation)
        }
        queue = task
        return task
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard isEnabled else { return }
        running += 1
        status = .syncing
        defer { running -= 1 }
        do {
            try await operation()
            if running == 1 {
                status = .ok
                message = nil
                lastSync = .now
            }
        } catch let error as BCWError where error.isUnauthorized {
            model?.cloudSessionExpired()
        } catch let error as BCWError where error.code == "not_found" {
            // Account scollegato da un altro dispositivo: l'elenco aggiornato lo toglie.
            status = .idle
            Task { await self.model?.refreshCloud(force: true) }
        } catch {
            status = (error as? BCWError)?.isOffline == true ? .offline : .failed
            message = error.localizedDescription
        }
    }

    /// Esegue un'operazione dopo una breve attesa (più modifiche di seguito, un solo invio).
    private func schedule(_ key: String, delay: Duration, _ operation: @escaping () async throws -> Void) {
        timers[key]?.cancel()
        waiting[key] = operation
        timers[key] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.timers[key] = nil
            if let operation = self.waiting.removeValue(forKey: key) { self.enqueue(operation) }
        }
    }

    /// Invia subito le modifiche in attesa (es. quando l'app va in secondo piano).
    func flush() async {
        for timer in timers.values { timer.cancel() }
        timers = [:]
        let operations = waiting
        waiting = [:]
        var last: Task<Void, Never>?
        for operation in operations.values { last = enqueue(operation) }
        await last?.value
    }

    /// Come `flush()`, ma aspetta al massimo `timeout` (uscita dall'account BCW).
    func flush(timeout: Duration) async {
        let once = Once()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                await self.flush()
                once.finish(continuation)
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.finish(continuation)
            }
        }
    }

    /// Riprende una continuazione una sola volta (vince chi arriva prima).
    private final class Once {
        private var done = false

        func finish(_ continuation: CheckedContinuation<Void, Never>) {
            guard !done else { return }
            done = true
            continuation.resume()
        }
    }

    // MARK: Impostazioni

    private func localSettings() -> [String: JSONValue] {
        guard let model else { return [:] }
        return model.preferences.syncedValues.merging(ThemeStore.shared.syncedValues) { first, _ in first }
    }

    private func applySettings(_ values: [String: JSONValue]) {
        isApplying = true
        model?.preferences.applySynced(values)
        ThemeStore.shared.applySynced(values)
        isApplying = false
        model?.settingsApplied()
    }

    func settingsChanged() {
        guard isEnabled, !isApplying else { return }
        schedule("settings", delay: .seconds(1.5)) { [weak self] in try await self?.syncSettings(fetchFirst: false) }
    }

    func pullSettings() {
        guard isEnabled else { return }
        enqueue { [weak self] in try await self?.syncSettings(fetchFirst: true) }
    }

    /// Unione a tre vie: le chiavi cambiate qui dall'ultima sincronizzazione vincono, le altre
    /// arrivano dal server. La prima volta su un dispositivo vince il server.
    private func syncSettings(fetchFirst: Bool) async throws {
        guard let token else { return }
        let previous = state.settingsSnapshot
        var remote: (data: [String: JSONValue]?, version: Int) = (state.settingsRemote, state.settingsVersion)
        if fetchFirst {
            let document = try await BCWAPI.document(token: token, path: "/sync/settings")
            remote = (document.data.flatMap(Self.decodeObject), document.version)
        }
        for _ in 0..<3 {
            let local = localSettings()
            var merged: [String: JSONValue]
            if let data = remote.data, remote.version > 0 {
                guard let previous else {
                    applySettings(data)
                    finishSettings(version: remote.version, data: data)
                    return
                }
                let changed = local.keys.filter { local[$0] != previous[$0] }
                merged = data
                for key in changed { merged[key] = local[key] }
                if local.contains(where: { merged[$0.key] != $0.value }) { applySettings(merged) }
                if changed.isEmpty {
                    finishSettings(version: remote.version, data: data)
                    return
                }
            } else {
                merged = (remote.data ?? [:]).merging(local) { _, new in new }
            }
            do {
                let body = try JSONEncoder().encode(merged)
                let version = try await BCWAPI.putDocument(token: token, path: "/sync/settings", data: body,
                                                           baseVersion: remote.version)
                finishSettings(version: version, data: merged)
                return
            } catch let error as BCWError where error.code == "conflict" {
                remote = (error.document.flatMap(Self.decodeObject), error.version ?? 0)
            }
        }
    }

    private func finishSettings(version: Int, data: [String: JSONValue]) {
        state.settingsVersion = version
        state.settingsSnapshot = localSettings()
        state.settingsRemote = data
        saveState()
    }

    private static func decodeObject(_ data: Data) -> [String: JSONValue]? {
        try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    // MARK: Orario

    private func isCloudAccount(_ id: String) -> Bool {
        guard let model, model.cloud != nil else { return false }
        return model.accounts.contains { $0.id == id }
    }

    func timetableChanged(owner: String) {
        guard isEnabled, !isApplying, isCloudAccount(owner) else { return }
        schedule("timetable:\(owner)", delay: .seconds(2)) { [weak self] in
            try await self?.syncTimetable(owner, fetchFirst: false)
        }
    }

    func pullTimetable(_ id: String) {
        guard isCloudAccount(id) else { return }
        enqueue { [weak self] in try await self?.syncTimetable(id, fetchFirst: true) }
    }

    func forgetTimetable(_ id: String) {
        let key = "timetable:\(id)"
        timers[key]?.cancel()
        timers[key] = nil
        waiting[key] = nil
        state.timetables[id] = nil
        saveState()
    }

    private func syncTimetable(_ id: String, fetchFirst: Bool) async throws {
        guard let token, isCloudAccount(id) else { return }
        let saved = state.timetables[id] ?? TimetableState(version: 0, hash: nil)
        let neverSynced = saved.version == 0 && saved.hash == nil
        var remote: (data: Data?, version: Int) = (nil, saved.version)
        if fetchFirst {
            let document = try await BCWAPI.document(token: token, path: "/sync/timetable/\(id)")
            remote = (document.data, document.version)
        }
        for _ in 0..<3 {
            guard let local = TimetableStore.storedData(owner: id) else {
                // Nessun orario su questo dispositivo: si prende quello del server, se c'è.
                if remote.version > 0, let data = remote.data { applyTimetable(id, data: data, version: remote.version) }
                return
            }
            let hash = Self.fingerprint(local)
            let dirty = !neverSynced && hash != saved.hash
            let base: Int
            if remote.version == 0 {
                base = 0
            } else if neverSynced, let data = remote.data {
                applyTimetable(id, data: data, version: remote.version)
                return
            } else if remote.version == saved.version {
                guard dirty else { return }
                base = saved.version
            } else if !dirty, let data = remote.data {
                applyTimetable(id, data: data, version: remote.version)
                return
            } else {
                base = remote.version
            }
            try await uploadFiles(id, timetable: local)
            do {
                let version = try await BCWAPI.putDocument(token: token, path: "/sync/timetable/\(id)", data: local,
                                                           baseVersion: base)
                state.timetables[id] = TimetableState(version: version, hash: hash)
                saveState()
                return
            } catch let error as BCWError where error.code == "conflict" {
                remote = (error.document, error.version ?? 0)
            }
        }
    }

    private func applyTimetable(_ id: String, data: Data, version: Int) {
        guard let model else { return }
        isApplying = true
        let stored = model.timetable.applyRemote(owner: id, data: data)
        isApplying = false
        state.timetables[id] = TimetableState(version: version, hash: stored.map(Self.fingerprint))
        saveState()
        Task { await self.downloadMissingFiles(id) }
    }

    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: File dell'orario

    private static func referencedFiles(_ data: Data) -> Set<String> {
        (try? TimetableBackup.decoder().decode(Timetable.self, from: data))?.referencedFiles ?? []
    }

    private func uploadFiles(_ id: String, timetable: Data) async throws {
        guard let token else { return }
        let names = Self.referencedFiles(timetable)
        guard !names.isEmpty else { return }
        let present = try await BCWAPI.fileNames(token: token, accountID: id)
        for name in names.sorted() where !present.contains(name) {
            guard let data = try? Data(contentsOf: TimetableStore.fileURL(owner: id, name: name)) else { continue }
            do {
                try await BCWAPI.upload(token: token, accountID: id, name: name, data: data)
            } catch let error as BCWError where error.code == "quota_exceeded" || error.code == "too_large" {
                // Un file troppo grande o lo spazio esaurito non fermano l'orario.
                fileWarning = error.message
            }
        }
    }

    private func downloadMissingFiles(_ id: String) async {
        guard let data = TimetableStore.storedData(owner: id) else { return }
        for name in Self.referencedFiles(data).sorted()
        where !FileManager.default.fileExists(atPath: TimetableStore.fileURL(owner: id, name: name).path) {
            _ = await downloadFile(owner: id, name: name)
        }
    }

    /// Scarica un file dell'orario che manca su questo dispositivo; `true` se ora c'è.
    func downloadFile(owner: String, name: String) async -> Bool {
        guard let token, isCloudAccount(owner) else { return false }
        do {
            let data = try await BCWAPI.download(token: token, accountID: owner, name: name)
            try TimetableStore.writeFile(data, owner: owner, name: name)
            return true
        } catch {
            return false
        }
    }
}
