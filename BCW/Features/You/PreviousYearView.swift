import QuickLook
import SafariServices
import SwiftUI

/// Anni precedenti: le pagelle si scaricano nell'app, il resto dell'archivio
/// (voti, assenze, note) si consulta sul sito di Classeviva, perché l'API non lo fornisce.
struct PreviousYearView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var startYear = ArchiveModel.previousStartYear
    @State private var previewURL: URL?
    @State private var downloading: String?
    @State private var error: String?
    @State private var showingWeb = false

    /// L'archivio appartiene alla sessione: cambiando account o uscendo dalla demo viene azzerato.
    private var archive: ArchiveModel { model.archive(for: startYear) }

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    webArchiveCard
                    documentsSection
                }
                .pagePadding()
                .padding(.bottom, 32)
            }
            .tracksPageScroll()
            .themedBackground()
        }
        .pageChrome("Anno \(archive.title)", style: .inline) {
            BarMenu(icon: "calendarClock", label: "Scegli l'anno") {
                MenuPicker(title: "Anno scolastico", selection: $startYear,
                           options: ArchiveModel.availableStartYears.map { ($0, ArchiveModel.title(startYear: $0), nil) })
            }
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showingWeb) {
            SafariView(url: ArchiveModel.webURL)
                .ignoresSafeArea()
        }
        .task(id: "\(model.sessionID)-\(startYear)") {
            error = nil
            await load()
        }
    }

    // MARK: Archivio sul web

    private var webArchiveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(icon: "compass", tint: Theme.neutral)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Voti, assenze e note")
                        .font(.m3(16, weight: 550))
                        .foregroundStyle(Theme.ink)
                    Text("Disponibili sul sito di Classeviva")
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Text("Classeviva non rende disponibili all'app i dati degli anni passati. Accedi al sito e, dal menu principale, scegli \"Vai all'a.s. \(archive.title)\".")
                .font(.m3(14))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingWeb = true
            } label: {
                Label { Text("Apri l'archivio di Classeviva") } icon: { Icon("externalLink") }
            }
            .buttonStyle(.m3(.filled, size: .m, wide: true))
        }
        .card()
    }

    // MARK: Pagelle

    @ViewBuilder
    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Pagelle e documenti", subtitle: "Anno scolastico \(archive.title)")

            if let error { StatusBanner(message: error, icon: "alertTriangle") }

            switch archive.state {
            case .idle, .loading:
                LoadingCard(text: "Accesso all'archivio \(archive.title)…")
            case .failed(let message):
                unavailable(message)
            case .loaded:
                if archive.documents.isEmpty {
                    unavailable(archive.documentsError.map { "Classeviva ha risposto: \($0)" }
                                ?? "La scuola non ha pubblicato documenti per questo anno.")
                } else {
                    CardGrid(minWidth: 320, spacing: 12) {
                        ForEach(archive.documents) { doc in
                            DocumentButton(title: doc.title, isLoading: downloading == doc.id) {
                                Task { await open(doc) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func unavailable(_ message: String) -> some View {
        EmptyState("Nessun documento", icon: "fileText", description: message) {
            Button("Riprova") {
                _ = model.reloadArchive(for: startYear)
                Task { await load() }
            }
            .buttonStyle(.m3(.tonal))
        }
        .card()
    }

    private func load() async {
        await archive.load(credentials: model.credentialsForArchive, demo: model.isDemo)
    }

    private func open(_ doc: ReportDocument) async {
        downloading = doc.id
        defer { downloading = nil }
        do {
            previewURL = try await archive.downloadDocument(doc)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Browser di Safari dentro l'app: condivide le password salvate e i cookie di Safari.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.primary)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
