import QuickLook
import SwiftUI

struct NoticeboardView: View {
    private static let searchPrompt = "Cerca nelle comunicazioni"
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

    /// Su macOS, comunicazione aperta nel pannello di destra.
    @State private var selection: Notice.ID?
    /// Solo il passaggio conta (la larghezza cambierebbe a ogni fotogramma).
    @State private var isWide = true

    /// Elenco e dettaglio affiancati, come in Mail (solo su macOS e se c'è spazio).
    private var isSplit: Bool { Platform.isMac && isWide }

    var body: some View {
        Group {
            if isSplit {
                splitView
            } else {
                ScrollView {
                    list
                        .pagePadding()
                        .padding(.bottom, 32)
                }
                .tracksPageScroll()
            }
        }
        .themedBackground()
        .onGeometryChange(for: Bool.self) { $0.size.width >= 820 } action: { isWide = $0 }
        #if DEBUG
        .onAppear {
            // Per gli screenshot di sviluppo: `-BCWOpenNotice YES` apre la prima comunicazione.
            if UserDefaults.standard.bool(forKey: "BCWOpenNotice") { selection = model.notices.first?.id }
        }
        #endif
        .pageChrome("Bacheca", subtitle: Platform.isMac ? unreadSubtitle : nil, style: .inline)
        .localSearchable(text: $search, prompt: Self.searchPrompt)
        .refreshable { await model.loadNotices() }
    }

    private var unreadSubtitle: String? {
        let unread = model.unreadNoticesCount
        return unread == 0 ? nil : (unread == 1 ? "1 da leggere" : "\(unread) da leggere")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
            LocalSearchField(text: $search, prompt: Self.searchPrompt)
            #else
            PageSearchBar(text: $search, prompt: Self.searchPrompt)
            #endif
            ChipRow {
                FilterChip(title: "Da leggere", icon: "circleFill", isSelected: onlyUnread) {
                    onlyUnread.toggle()
                }
                FilterChip(title: "Tutte", isSelected: category == nil) { category = nil }
                ForEach(categories, id: \.self) { c in
                    FilterChip(title: c, isSelected: category == c) {
                        category = category == c ? nil : c
                    }
                }
            }

            if filtered.isEmpty {
                EmptyState(model.notices.isEmpty ? "Bacheca vuota" : "Nessun risultato", icon: "megaphone",
                           description: model.notices.isEmpty ? "Le comunicazioni della scuola appariranno qui." : "Prova a cambiare i filtri.")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { notice in
                        if isSplit {
                            Button {
                                selection = notice.id
                            } label: {
                                NoticeRow(notice: notice, isSelected: selection == notice.id)
                            }
                            .buttonStyle(.pressable(radius: selection == notice.id ? Theme.radii.xl : Theme.radii.li))
                        } else {
                            NavigationLink {
                                NoticeDetailView(notice: notice)
                                    .pageChrome(Platform.isMac ? "Comunicazione" : "", style: .inline)
                            } label: {
                                NoticeRow(notice: notice)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
            }
        }
        .animation(Motion.spatial, value: filtered)
    }

    private var splitView: some View {
        HStack(spacing: 0) {
            ScrollView {
                list
                    .padding(.leading, 28)
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                    .padding(.bottom, Theme.bottomInset)
            }
            .frame(width: 420)

            Group {
                if let notice = model.notices.first(where: { $0.id == selection }) {
                    NoticeDetailView(notice: notice)
                        .id(notice.id)
                } else {
                    EmptyState("Nessuna comunicazione aperta", icon: "megaphone",
                               description: "Scegli una comunicazione dall'elenco per leggerla.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surfaceContainerLow, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
            .padding(.leading, 4)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
    }
}

private struct NoticeRow: View {
    let notice: Notice
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(notice.isRead ? Color.clear : Theme.primary)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .font(.m3(15, weight: notice.isRead ? 500 : 700))
                    .foregroundStyle(isSelected ? Theme.onSecondaryContainer : Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(notice.category)
                        .font(.m3(12, weight: 650))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                    if let date = notice.publishedAt {
                        Text(date.shortDayWithYear)
                            .font(.m3(12))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer()
                    if notice.hasAttachments || !notice.attachments.isEmpty {
                        Icon("paperclip", size: 18)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    if notice.requiresAction {
                        Pill(text: notice.needsSign ? "Da firmare" : (notice.needsJoin ? "Adesione" : "Risposta"),
                             color: Theme.fair, small: true)
                    }
                }
            }
        }
        .card(padding: 14, color: isSelected ? Theme.secondaryContainer : nil,
              radius: isSelected ? Theme.radii.xl : nil)
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
    @State private var confirmJoin = false
    @State private var confirmSign = false

    enum Action { case join, sign }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: notice.category, color: Theme.primary)
                    Text(detail?.title?.nilIfEmpty ?? notice.title)
                        .font(.m3(26, weight: 500, rounded: true))
                        .foregroundStyle(Theme.ink)
                    if let date = notice.publishedAt {
                        Text("Pubblicata \(date.longDay.lowercased()) \(date.it("yyyy"))")
                            .font(.m3(13))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    if let from = notice.validFrom, let to = notice.validTo {
                        Text("Valida dal \(from.shortDay) al \(to.shortDayWithYear)")
                            .font(.m3(13))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }

                if loading {
                    LoadingCard()
                } else if let error {
                    StatusBanner(message: error, icon: "alertTriangle")
                } else if let text = detail?.text?.nilIfEmpty {
                    Text(text)
                        .font(.m3(15))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .lineSpacing(8)
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
                                    IconBadge(icon: "fileText", tint: Theme.neutral, size: 34)
                                    Text(attachment.fileName)
                                        .font(.m3(15))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if downloading == attachment.number {
                                        InlineProgress()
                                    } else {
                                        Icon("download")
                                            .foregroundStyle(Theme.primary)
                                    }
                                }
                                .card(padding: 12)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }

                actions
            }
            .padding(.horizontal, Platform.isMac ? 28 : 16)
            .padding(.top, Platform.isMac ? 24 : 4)
            .padding(.bottom, 32)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tracksPageScroll()
        .quickLookPreview($previewURL)
        .m3Dialog("Confermi?", isPresented: $confirmJoin, message: "La tua adesione verrà inviata alla scuola.") {
            [.cancel(), DialogAction(title: "Aderisci", style: .strong) { Task { await perform(.join) } }]
        }
        .m3Dialog("Confermi?", isPresented: $confirmSign, message: "Confermerai la presa visione della comunicazione.") {
            [.cancel(), DialogAction(title: "Conferma e firma", style: .strong) { Task { await perform(.sign) } }]
        }
        .task { await load() }
    }

    @ViewBuilder
    private var actions: some View {
        if notice.needsJoin || notice.needsSign || notice.needsReply, let detail {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Richiesta della scuola")
                if notice.needsJoin {
                    if detail.joined {
                        StatusLine(text: "Hai aderito", icon: "checkSealFill", color: Theme.good)
                    } else {
                        Button { confirmJoin = true } label: { Label { Text("Aderisci") } icon: { Icon("thumbsUp") } }
                            .buttonStyle(.m3(.filled))
                    }
                }
                if notice.needsSign {
                    if detail.signed {
                        StatusLine(text: "Presa visione confermata", icon: "checkSealFill", color: Theme.good)
                    } else {
                        Button { confirmSign = true } label: { Label { Text("Conferma presa visione") } icon: { Icon("signature") } }
                            .buttonStyle(.m3(.filled))
                    }
                }
                if notice.needsReply {
                    if let reply = detail.replyText {
                        Text("La tua risposta: \(reply)")
                            .font(.m3(15))
                            .foregroundStyle(Theme.secondaryInk)
                    } else {
                        TextField("Scrivi una risposta", text: $replyText, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.m3(16))
                            .textFieldStyle(.plain)
                            .padding(16)
                            .frame(minHeight: 96, alignment: .topLeading)
                            .background(Theme.surfaceContainerHighest, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
                        Button { Task { await reply() } } label: { Label { Text("Invia risposta") } icon: { Icon("send") } }
                            .buttonStyle(.m3(.tonal))
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
