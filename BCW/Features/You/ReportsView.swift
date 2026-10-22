import QuickLook
import SwiftUI

struct ReportsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var loading = false
    @State private var previewURL: URL?
    @State private var downloading: String?
    @State private var error: String?
    /// iPad largo con la pagina larga almeno 792 punti: riepilogo a sinistra, documenti a destra.
    @State private var isSplit = false

    var body: some View {
        content
            .pageChrome("Scrutini", style: .inline)
            .quickLookPreview($previewURL)
            .task {
                loading = true
                error = await model.loadDocuments()
                loading = false
            }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error {
            StatusBanner(message: error, icon: "alertTriangle")
        }
    }

    private var content: some View {
        ZStack {
            if isSplit {
                SplitPage(sideWidth: 380, refresh: { error = await model.loadDocuments() }) {
                    periodSummary
                } main: {
                    VStack(alignment: .leading, spacing: 18) {
                        errorBanner
                        documentsList
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        errorBanner
                        periodSummary
                        documentsList
                    }
                    .pagePadding()
                    .padding(.bottom, 32)
                }
                .tracksPageScroll()
                .refreshable { error = await model.loadDocuments() }
            }
        }
        // Sull'iPad largo, da 792 punti di pagina, in due colonne (come la versione web).
        .widthAtLeast(SplitMetrics.threshold, isOn: $isSplit)
        .themedBackground()
    }

    @ViewBuilder
    private var documentsList: some View {
        if loading && model.documents == nil {
            LoadingCard()
        } else if let documents = model.documents {
            if documents.documents.isEmpty && documents.schoolReports.isEmpty {
                EmptyState("Nessun documento", icon: "fileText",
                           description: "Pagelle e documenti di valutazione appariranno qui dopo gli scrutini.")
            }
            if !documents.documents.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Documenti")
                    CardGrid(minWidth: 320, spacing: 12) {
                        ForEach(documents.documents) { doc in
                            DocumentButton(title: doc.title, isLoading: downloading == doc.id) {
                                Task { await open(doc) }
                            }
                        }
                    }
                }
            }
            if !documents.schoolReports.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Pagelle online", subtitle: "Si aprono sul sito di Classeviva")
                    CardGrid(minWidth: 320, spacing: 12) {
                        ForEach(documents.schoolReports) { report in
                            DocumentButton(title: report.title, icon: "compass", trailingIcon: "externalLink", isLoading: false) {
                                if let link = report.viewLink, let url = URL(string: link) { openURL(url) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Riepilogo delle medie per periodo, utile in vista degli scrutini.
    private var periodSummary: some View {
        let book = model.gradeBook
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Situazione per periodo")
            ForEach(book.activePeriods) { period in
                let subjects = book.subjects(in: period.position)
                let below = subjects.filter { ($0.average ?? 10) < 6 }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(period.name)
                            .font(.m3(16, weight: 550))
                            .foregroundStyle(Theme.ink)
                        Text(below.isEmpty ? "Nessuna insufficienza"
                             : "Insufficienze: " + below.map(\.name).joined(separator: ", "))
                            .font(.m3(12))
                            .foregroundStyle(below.isEmpty ? Theme.good : Theme.poor)
                    }
                    Spacer()
                    Text(GradeFormat.average(book.average(period: period.position)))
                        .font(.numeral(28))
                        .foregroundStyle(Theme.gradeColor(value: book.average(period: period.position)))
                }
            }
            if book.activePeriods.isEmpty {
                Text("Nessun voto registrato.")
                    .font(.m3(14))
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .card()
    }

    private func open(_ doc: ReportDocument) async {
        downloading = doc.id
        defer { downloading = nil }
        do {
            previewURL = try await model.downloadDocument(doc)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DocumentButton: View {
    let title: String
    var icon = "fileText"
    var trailingIcon = "chevronRight"
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(icon: icon, tint: Theme.neutral)
                Text(title)
                    .font(.m3(16, weight: 500))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isLoading {
                    InlineProgress()
                } else {
                    Icon(trailingIcon, size: 22)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            .card(padding: 14)
        }
        .buttonStyle(.pressable)
        .disabled(isLoading)
    }
}
