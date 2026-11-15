import Foundation
import OSLog
import SwiftUI

/// Una release di BCW su GitHub (`api.github.com/repos/kubos5/BCW/releases`).
struct GitHubRelease: Decodable, Equatable, Identifiable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: URL
    let publishedAt: Date?
    let draft: Bool?
    let prerelease: Bool?

    var id: String { tagName }
    var version: AppVersion { AppVersion(tagName) }
}

/// Numero di versione confrontabile ("v3.3.1", "4.0" → [3, 3, 1], [4, 0]; le parti mancanti valgono 0).
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces).drop { !$0.isNumber }
        parts = trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        for index in 0..<max(a.parts.count, b.parts.count) {
            let x = index < a.parts.count ? a.parts[index] : 0
            let y = index < b.parts.count ? b.parts[index] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// La versione dell'app installata.
    static var installed: String {
        #if DEBUG
        // Per le prove: `-BCWInstalledVersion 3.3` fa come se fosse installata quella versione.
        if let version = UserDefaults.standard.string(forKey: "BCWInstalledVersion") { return version }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// Note di rilascio e nuove versioni (richiesta dell'utente, 4.0), dalle release di GitHub:
/// - dopo un aggiornamento dell'app (in tutte e due le build) un foglio mostra le note della release
///   di quella versione; mai alla prima apertura;
/// - solo nella build GitHub, all'apertura (al massimo ogni 12 ore) un foglio avvisa se su GitHub c'è
///   una versione più recente, con le sue note. Si spegne per sempre da Impostazioni › Generale (o dal
///   foglio). Nella build dell'App Store no: le versioni nuove le installa l'App Store.
/// Le richieste vanno solo a `api.github.com` e non portano dati dell'utente.
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repository = "kubos5/BCW"

    enum Sheet: Identifiable, Equatable {
        /// Le novità della versione appena installata.
        case releaseNotes(GitHubRelease)
        /// Una versione più recente su GitHub (build GitHub).
        case update(GitHubRelease)

        var id: String {
            switch self {
            case let .releaseNotes(release): "notes-\(release.tagName)"
            case let .update(release): "update-\(release.tagName)"
            }
        }
    }

    enum CheckResult { case upToDate, available, failed }

    /// Il foglio da mostrare (`RootView`).
    var sheet: Sheet?

    private static let lastVersionKey = "lastRunVersion"
    private static let pendingNotesKey = "pendingReleaseNotes"
    private static let lastCheckKey = "updateCheckedAt"
    private static let snoozedVersionKey = "updateSnoozedVersion"
    private static let snoozedUntilKey = "updateSnoozedUntil"
    /// Ogni quanto si controlla la versione più recente (build GitHub).
    private static let checkInterval: TimeInterval = 12 * 60 * 60
    /// "Più tardi": la stessa versione non viene riproposta per 3 giorni.
    private static let snoozeInterval: TimeInterval = 3 * 24 * 60 * 60
    private static let log = Logger(subsystem: "com.bcw-classeviva.app", category: "Updates")

    @ObservationIgnored private var didLaunch = false
    @ObservationIgnored private var isRunning = false

    private init() {}

    /// All'avvio: ricorda la versione e, se l'app è stata aggiornata (non alla prima apertura), mette in
    /// attesa le note della versione nuova. Chi aggiorna dalla 3.3.1 o prima non ha la versione salvata.
    func launch() {
        guard !didLaunch, ProtectedData.isAvailableAtLaunch else { return }
        didLaunch = true
        let defaults = UserDefaults.standard
        let installed = AppVersion.installed
        let last = defaults.string(forKey: Self.lastVersionKey)
        defaults.set(installed, forKey: Self.lastVersionKey)
        #if DEBUG
        // Per le prove: `-BCWReleaseNotes YES` mostra le note come dopo un aggiornamento.
        if defaults.bool(forKey: "BCWReleaseNotes") {
            defaults.set(installed, forKey: Self.pendingNotesKey)
            return
        }
        #endif
        guard !Onboarding.isFirstRun else { return }
        if let last, AppVersion(last) >= AppVersion(installed) { return }
        defaults.set(installed, forKey: Self.pendingNotesKey)
    }

    /// Con l'app in primo piano e pronta (niente introduzione né blocco): le note in attesa o, nella
    /// build GitHub, l'avviso della versione nuova.
    func presentIfNeeded(updateAlerts: Bool) async {
        guard didLaunch, !isRunning, sheet == nil else { return }
        isRunning = true
        defer { isRunning = false }
        if await presentPendingNotes() { return }
        guard !BuildVariant.isAppStore, updateAlerts, !Onboarding.isFirstRun else { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.checkInterval { return }
        _ = await check(manual: false)
    }

    /// "Cerca aggiornamenti" (Impostazioni › Generale): ignora l'intervallo e il "più tardi".
    func checkNow() async -> CheckResult {
        await check(manual: true)
    }

    enum NotesResult { case shown, unavailable, failed }

    /// "Note di rilascio" (Impostazioni › Generale; richiesta dell'utente, 4.0): le novità della versione
    /// installata o, se la sua release non c'è, dell'ultima pubblicata. Nella build GitHub, con una
    /// versione più recente su GitHub, il foglio della versione nuova (con le sue note e lo scaricamento).
    func showLatestNotes() async -> NotesResult {
        guard let releases = await fetchReleases() else { return .failed }
        let published = releases.filter { $0.draft != true && $0.prerelease != true }
        guard let latest = published.max(by: { $0.version < $1.version }) else { return .unavailable }
        let installed = AppVersion(AppVersion.installed)
        if !BuildVariant.isAppStore, latest.version > installed {
            withAnimation(Motion.spatial) { sheet = .update(latest) }
        } else {
            let release = published.first { $0.version == installed } ?? latest
            withAnimation(Motion.spatial) { sheet = .releaseNotes(release) }
        }
        return .shown
    }

    /// "Più tardi" nel foglio della versione nuova.
    func snooze(_ release: GitHubRelease) {
        UserDefaults.standard.set(release.tagName, forKey: Self.snoozedVersionKey)
        UserDefaults.standard.set(Date().addingTimeInterval(Self.snoozeInterval), forKey: Self.snoozedUntilKey)
    }

    // MARK: Note della versione installata

    private func presentPendingNotes() async -> Bool {
        let defaults = UserDefaults.standard
        guard let pending = defaults.string(forKey: Self.pendingNotesKey) else { return false }
        // Le note in attesa di una versione diversa da quella installata non servono più.
        guard AppVersion(pending) == AppVersion(AppVersion.installed) else {
            defaults.removeObject(forKey: Self.pendingNotesKey)
            return false
        }
        guard let releases = await fetchReleases() else { return false } // si riprova alla prossima apertura
        let installed = AppVersion(AppVersion.installed)
        let published = releases.filter { $0.draft != true }
        // La release di questa versione; se non c'è ancora, l'ultima pubblicata purché non più vecchia.
        var latest = published.filter { $0.prerelease != true }.max { $0.version < $1.version }
        #if DEBUG
        // Con `-BCWReleaseNotes YES` anche una release più vecchia (per vedere il foglio prima di pubblicarla).
        let anyRelease = defaults.bool(forKey: "BCWReleaseNotes")
        #else
        let anyRelease = false
        #endif
        if let release = latest, release.version < installed, !anyRelease { latest = nil }
        let release = published.first { $0.version == installed } ?? latest
        guard let release else { return false }
        defaults.removeObject(forKey: Self.pendingNotesKey)
        withAnimation(Motion.spatial) { sheet = .releaseNotes(release) }
        return true
    }

    // MARK: Versione nuova (build GitHub)

    private func check(manual: Bool) async -> CheckResult {
        guard let release = await fetchLatest() else { return .failed }
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: Self.lastCheckKey)
        guard release.version > AppVersion(AppVersion.installed) else { return .upToDate }
        if !manual, defaults.string(forKey: Self.snoozedVersionKey) == release.tagName,
           let until = defaults.object(forKey: Self.snoozedUntilKey) as? Date, until > Date() {
            return .available
        }
        withAnimation(Motion.spatial) { sheet = .update(release) }
        return .available
    }

    // MARK: Rete

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)\(path)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BCW-iOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        return request
    }

    private func fetchReleases() async -> [GitHubRelease]? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request("/releases?per_page=20"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try Self.decoder.decode([GitHubRelease].self, from: data)
        } catch {
            Self.log.error("Release non scaricate: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchLatest() async -> GitHubRelease? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request("/releases/latest"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try Self.decoder.decode(GitHubRelease.self, from: data)
        } catch {
            Self.log.error("Ultima release non scaricata: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
