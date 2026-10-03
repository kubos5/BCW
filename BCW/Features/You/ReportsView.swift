import QuickLook
import SwiftUI

struct ReportsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var loading = false
    @State private var previewURL: URL?
    @State private var downloading: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error {
                    StatusBanner(message: error, symbol: "exclamationmark.triangle")
                }

                periodSummary

                if loading && model.documents == nil {
                    LoadingCard()
                } else if let documents = model.documents {
                    if documents.documents.isEmpty && documents.schoolReports.isEmpty {
                        ContentUnavailableView("Nessun documento", systemImage: "doc.text",
                                               description: Text("Pagelle e documenti di valutazione appariranno qui dopo gli scrutini."))
                            .padding(.top, 20)
                    }
                    if !documents.documents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Documenti")
                            ForEach(documents.documents) { doc in
                                DocumentButton(title: doc.title, isLoading: downloading == doc.id) {
                                    Task { await open(doc) }
                                }
                            }
                        }
                    }
                    if !documents.schoolReports.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Pagelle online", subtitle: "Si aprono sul sito di Classeviva")
                            ForEach(documents.schoolReports) { report in
                                DocumentButton(title: report.title, symbol: "safari", isLoading: false) {
                                    if let link = report.viewLink, let url = URL(string: link) { openURL(url) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .navigationTitle("Scrutini")
        .quickLookPreview($previewURL)
        .task {
            loading = true
            error = await model.loadDocuments()
            loading = false
        }
        .refreshable { error = await model.loadDocuments() }
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
                        Text(period.name).font(.headline).foregroundStyle(Theme.ink)
                        Text(below.isEmpty ? "Nessuna insufficienza"
                             : "Insufficienze: " + below.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(below.isEmpty ? Theme.good : Theme.poor)
                    }
                    Spacer()
                    Text(GradeFormat.average(book.average(period: period.position)))
                        .font(.numeral(22, weight: .bold))
                        .foregroundStyle(Theme.gradeColor(value: book.average(period: period.position)))
                }
            }
            if book.activePeriods.isEmpty {
                Text("Nessun voto registrato.")
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
    var symbol = "doc.richtext"
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, tint: Theme.neutral)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
