import QuickLook
import SwiftUI

struct NoticeboardView: View {
    private static let searchPrompt = "Cerca nelle comunicazioni"
    @Environment(AppModel.self) private var model
    @Environment(\.windowClass) private var windowClass
    @Environment(\.pageGutter) private var gutter
    @State private var search = ""
    @State private var category: String?
    @State private var onlyUnread = false
    /// iPad largo con la pagina larga almeno 792 punti: elenco e comunicazione affiancati.
    @State private var isSplit = false
    /// Comunicazione aperta accanto all'elenco (pagina affiancata).
    @State private var selected: Notice.ID?
    /// Comunicazione aperta nella pila quando la pagina torna in colonna (es. ruotando l'iPad).
    @State private var collapsedNotice: Notice?

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

    /// Sull'iPad largo il numero delle comunicazioni da leggere sta sotto il titolo.
    private var subtitle: String? {
        let unread = model.unreadNoticesCount
        guard windowClass == .regular, unread > 0 else { return nil }
        return unread == 1 ? "1 da leggere" : "\(unread) da leggere"
    }

    var body: some View {
        // Calcolato una volta per aggiornamento (a ogni lettera della ricerca).
        let filtered = filtered
        ZStack {
            if isSplit {
                splitContent(filtered)
            } else {
                ScrollView {
                    list(filtered, selectable: false)
                        .pagePadding()
                        .padding(.bottom, 32)
                }
                .tracksPageScroll()
                .refreshable { await model.loadNotices() }
            }
        }
        // Sull'iPad largo, da 792 punti di pagina, come la posta: elenco a sinistra e la
        // comunicazione scelta a destra (come la versione web). Filtri e scelta stanno qui.
        .widthAtLeast(SplitMetrics.threshold, isOn: $isSplit)
        #if DEBUG
        // Script di prova (`-BCWScript`): apre la prima comunicazione nel pannello.
        .debugAction("notice") { selected = filtered.first?.id }
        #endif
        .themedBackground()
        .navigationDestination(item: $collapsedNotice) { notice in
            NoticeDetailView(notice: notice)
                .pageChrome("", style: .inline)
                // Di nuovo affiancata si chiude da sé e la comunicazione (ancora `selected`)
                // ricompare nel pannello.
                .dismissesWhenSplit()
        }
        // Sull'iPhone la pagina non si affianca mai, quindi questo non scatta.
        .onChange(of: isSplit) { _, split in
            if !split, let notice = model.notices.first(where: { $0.id == selected }) {
                collapsedNotice = notice
            }
        }
        .pageChrome("Bacheca", subtitle: subtitle, style: .inline)
        .localSearchable(text: $search, prompt: Self.searchPrompt)
    }

    /// Elenco a sinistra (scorre per conto suo) e la comunicazione scelta in un pannello.
    private func splitContent(_ filtered: [Notice]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                list(filtered, selectable: true)
                    .padding(.leading, gutter)
                    .padding(.trailing, SplitMetrics.sideTrailing)
                    .padding(.top, SplitMetrics.sideTop)
                    .padding(.bottom, SplitMetrics.bottom)
            }
            .scrollIndicators(.hidden)
            .tracksPageScroll()
            .scrollsToTopOnReselect()
            .refreshable { await model.loadNotices() }
            .frame(width: 380 + gutter + SplitMetrics.sideTrailing)

            ZStack {
                if let notice = model.notices.first(where: { $0.id == selected }) {
                    NoticeDetailView(notice: notice, insets: EdgeInsets(top: 24, leading: 28, bottom: 40, trailing: 28))
                        .id(notice.id)
                } else {
                    EmptyState("Nessuna comunicazione aperta", icon: "megaphone",
                               description: "Scegli una comunicazione dall'elenco per leggerla.")
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surfaceContainerLow, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
            .clipShape(.rect(cornerRadius: Theme.radii.xl, style: .continuous))
            .padding(.leading, 4)
            .padding(.trailing, gutter - 8)
            .padding(.bottom, gutter - 8)
        }
    }

    private func list(_ filtered: [Notice], selectable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PageSearchBar(text: $search, prompt: Self.searchPrompt)
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
                ListGroup {
                    ForEach(filtered) { notice in
                        if selectable {
                            // Pagina affiancata: la comunicazione si apre nel pannello accanto.
                            Button {
                                guard selected != notice.id else { return }
                                Haptics.selection()
                                selected = notice.id
                            } label: {
                                NoticeRow(notice: notice)
                            }
                            .buttonStyle(ListRowButtonStyle(selected: selected == notice.id))
                            .accessibilityAddTraits(selected == notice.id ? .isSelected : [])
                        } else {
                            NavigationLink {
                                NoticeDetailView(notice: notice)
                                    .pageChrome("", style: .inline)
                            } label: {
                                NoticeRow(notice: notice)
                            }
                            .buttonStyle(.listRow)
                        }
                    }
                }
            }
        }
        .animation(Motion.spatial, value: filtered)
    }
}

private struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(notice.isRead ? Color.clear : Theme.primary)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .font(.m3(15, weight: notice.isRead ? 500 : 700))
                    .foregroundStyle(Theme.ink)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NoticeDetailView: View {
    @Environment(AppModel.self) private var model
    let notice: Notice
    /// Margini del contenuto (più ampi nel pannello della Bacheca affiancata sull'iPad).
    var insets = EdgeInsets(top: 4, leading: 16, bottom: 32, trailing: 16)

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
            .padding(insets)
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
