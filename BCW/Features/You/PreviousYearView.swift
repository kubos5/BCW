import QuickLook
#if os(iOS)
import SafariServices
#endif
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
            #if os(macOS)
            SplitColumns(sideWidth: 360) {
                webArchiveCard
            } main: {
                documentsSection
            }
            #else
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    webArchiveCard
                    documentsSection
                }
                .pagePadding()
                .padding(.bottom, 24)
            }
            .themedBackground()
            #endif
        }
        .screenTitle("Anno \(archive.title)")
        .inlineTitleDisplay()
        .quickLookPreview($previewURL)
        #if os(iOS)
        .sheet(isPresented: $showingWeb) {
            SafariView(url: ArchiveModel.webURL)
                .ignoresSafeArea()
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                Menu {
                    Picker("Anno scolastico", selection: $startYear) {
                        ForEach(ArchiveModel.availableStartYears, id: \.self) { year in
                            Text(ArchiveModel.title(startYear: year)).tag(year)
                        }
                    }
                } label: {
                    Image(systemName: "calendar.badge.clock")
                }
                .accessibilityLabel("Scegli l'anno")
            }
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
                IconBadge(symbol: "safari", tint: Theme.neutral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voti, assenze e note")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("Disponibili sul sito di Classeviva")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Text("Classeviva non rende disponibili all'app i dati degli anni passati. Accedi al sito\(Platform.isMac ? ", che si apre nel browser," : "") e, dal menu principale, scegli \"Vai all'a.s. \(archive.title)\".")
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                // Su macOS il sito si apre nel browser predefinito, con le sue password salvate.
                #if os(macOS)
                openURL(ArchiveModel.webURL)
                #else
                showingWeb = true
                #endif
            } label: {
                Label("Apri l'archivio di Classeviva", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .card()
    }

    // MARK: Pagelle

    @ViewBuilder
    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Pagelle e documenti", subtitle: "Anno scolastico \(archive.title)")

            if let error { StatusBanner(message: error, symbol: "exclamationmark.triangle") }

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
                    CardGrid(minWidth: 320) {
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
        ContentUnavailableView {
            Label("Nessun documento", systemImage: "doc.text")
        } description: {
            Text(message)
        } actions: {
            Button("Riprova") {
                _ = model.reloadArchive(for: startYear)
                Task { await load() }
            }
            .glassButton()
        }
        .frame(maxWidth: .infinity)
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

#if os(iOS)
/// Browser di Safari dentro l'app: condivide le password salvate e i cookie di Safari.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.accent)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
