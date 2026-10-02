import QuickLook
import SwiftUI

struct NoticeboardView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var category: String?
    @State private var onlyUnread = false

    private var categories: [String] {
        Array(Set(model.notices.map(\.category))).sorted()
    }

    private var filtered: [Notice] {
        model.notices.filter { notice in
            (category == nil || notice.category == category)
                && (!onlyUnread || !notice.isRead)
                && (search.isEmpty || notice.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "Da leggere", symbol: "circle.fill", isSelected: onlyUnread) {
                            onlyUnread.toggle()
                        }
                        FilterChip(title: "Tutte", isSelected: category == nil) { category = nil }
                        ForEach(categories, id: \.self) { c in
                            FilterChip(title: c, isSelected: category == c) {
                                category = category == c ? nil : c
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()

                if filtered.isEmpty {
                    ContentUnavailableView(model.notices.isEmpty ? "Bacheca vuota" : "Nessun risultato",
                                           systemImage: "megaphone",
                                           description: Text(model.notices.isEmpty
                                                             ? "Le comunicazioni della scuola appariranno qui."
                                                             : "Prova a cambiare i filtri."))
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { notice in
                            NavigationLink {
                                NoticeDetailView(notice: notice)
                            } label: {
                                NoticeRow(notice: notice)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.snappy, value: filtered)
        }
        .themedBackground()
        .navigationTitle("Bacheca")
        .searchable(text: $search, prompt: "Cerca nelle comunicazioni")
        .refreshable { await model.loadNotices() }
    }
}

private struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(notice.isRead ? Color.clear : Theme.accent)
                .frame(width: 9, height: 9)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .font(.body.weight(notice.isRead ? .regular : .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(notice.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    if let date = notice.publishedAt {
                        Text(date.shortDayWithYear)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer()
                    if notice.hasAttachments || !notice.attachments.isEmpty {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    if notice.requiresAction {
                        Text(notice.needsSign ? "Da firmare" : (notice.needsJoin ? "Adesione" : "Risposta"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.fair.opacity(0.15), in: .capsule)
                            .foregroundStyle(Theme.fair)
                    }
                }
            }
        }
        .card(padding: 14)
    }
}

struct NoticeDetailView: View {
    @Environment(AppModel.self) private var model
    let notice: Notice

    @State private var detail: NoticeDetail?
    @State private var error: String?
    @State private var loading = true
    @State private var previewURL: URL?
    @State private var downloading: Int?
    @State private var replyText = ""
    @State private var confirmAction: Action?

    enum Action: Identifiable {
        case join, sign
        var id: Int { self == .join ? 0 : 1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: notice.category, color: Theme.accent)
                    Text(detail?.title?.nilIfEmpty ?? notice.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let date = notice.publishedAt {
                        Text("Pubblicata \(date.longDay.lowercased()) \(date.it("yyyy"))")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    if let from = notice.validFrom, let to = notice.validTo {
                        Text("Valida dal \(from.shortDay) al \(to.shortDayWithYear)")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }

                if loading {
                    LoadingCard()
                } else if let error {
                    StatusBanner(message: error, symbol: "exclamationmark.triangle")
                } else if let text = detail?.text?.nilIfEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .card()
                }

                if !notice.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Allegati")
                        ForEach(notice.attachments) { attachment in
                            Button {
                                Task { await open(attachment) }
                            } label: {
                                HStack(spacing: 12) {
                                    IconBadge(symbol: "doc.richtext", tint: Theme.neutral, size: 34)
                                    Text(attachment.fileName)
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if downloading == attachment.number {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .card(padding: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                actions
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewURL)
        .task { await load() }
        .confirmationDialog("Confermi?", isPresented: Binding(get: { confirmAction != nil },
                                                             set: { if !$0 { confirmAction = nil } }),
                            presenting: confirmAction) { action in
            Button(action == .join ? "Aderisci" : "Conferma e firma") {
                Task { await perform(action) }
            }
        } message: { action in
            Text(action == .join ? "La tua adesione verrà inviata alla scuola."
                                 : "Confermerai la presa visione della comunicazione.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if notice.needsJoin || notice.needsSign || notice.needsReply, let detail {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Richiesta della scuola")
                if notice.needsJoin {
                    if detail.joined {
                        Label("Hai aderito", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.good)
                    } else {
                        Button("Aderisci", systemImage: "hand.thumbsup") { confirmAction = .join }
                            .buttonStyle(.glassProminent)
                    }
                }
                if notice.needsSign {
                    if detail.signed {
                        Label("Presa visione confermata", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.good)
                    } else {
                        Button("Conferma presa visione", systemImage: "signature") { confirmAction = .sign }
                            .buttonStyle(.glassProminent)
                    }
                }
                if notice.needsReply {
                    if let reply = detail.replyText {
                        Text("La tua risposta: \(reply)")
                            .foregroundStyle(Theme.secondaryInk)
                    } else {
                        TextField("Scrivi una risposta", text: $replyText, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(12)
                            .background(Theme.background, in: .rect(cornerRadius: 12, style: .continuous))
                        Button("Invia risposta", systemImage: "paperplane") {
                            Task { await reply() }
                        }
                        .buttonStyle(.glass)
                        .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .card()
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            detail = try await model.openNotice(notice)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func perform(_ action: Action) async {
        do {
            detail = try await model.openNotice(notice, join: action == .join ? true : nil,
                                                sign: action == .sign ? true : nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reply() async {
        do {
            detail = try await model.openNotice(notice, text: replyText)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func open(_ attachment: NoticeAttachment) async {
        downloading = attachment.number
        defer { downloading = nil }
        do {
            previewURL = try await model.downloadAttachment(attachment, of: notice)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
