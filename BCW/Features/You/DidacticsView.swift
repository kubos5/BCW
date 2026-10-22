import QuickLook
import SwiftUI

struct DidacticsView: View {
    private static let searchPrompt = "Cerca file o cartelle"
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.windowClass) private var windowClass
    @State private var teacherFilter: String?
    @State private var search = ""
    @State private var loading = false
    @State private var expandedFolders: Set<String> = []
    @State private var openingContent: Int?
    @State private var previewURL: URL?
    @State private var textItem: TextItem?
    @State private var error: String?

    struct TextItem: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    private var teachers: [DidacticTeacher] {
        model.didactics
            .filter { teacherFilter == nil || $0.id == teacherFilter }
            .sorted { ($0.lastShare ?? .distantPast) > ($1.lastShare ?? .distantPast) }
    }

    private func folders(of teacher: DidacticTeacher) -> [DidacticFolder] {
        teacher.folders
            .filter { folder in
                search.isEmpty || folder.name.localizedCaseInsensitiveContains(search)
                    || folder.contents.contains { $0.name.localizedCaseInsensitiveContains(search) }
            }
            .sorted { ($0.lastShare ?? .distantPast) > ($1.lastShare ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error {
                    StatusBanner(message: error, icon: "alertTriangle")
                }

                if !model.didactics.isEmpty {
                    PageSearchBar(text: $search, prompt: Self.searchPrompt)
                }

                if !model.didactics.isEmpty {
                    // Sull'iPad largo i docenti vanno a capo invece di scorrere di lato.
                    if windowClass == .regular {
                        FlowLayout(spacing: 8) { teacherChips }
                    } else {
                        ChipRow { teacherChips }
                    }
                }

                if loading && model.didactics.isEmpty {
                    LoadingCard()
                } else if model.didactics.isEmpty {
                    EmptyState("Nessun materiale", icon: "folder", description: "I file condivisi dai docenti appariranno qui.")
                }

                // Sull'iPad largo i docenti stanno in colonne.
                if windowClass == .regular {
                    AdaptiveColumns(minimum: 400, spacing: 18) { teacherGroups }
                } else {
                    teacherGroups
                }
            }
            .pagePadding()
            .padding(.bottom, 32)
            .animation(Motion.spatial, value: teacherFilter)
        }
        .tracksPageScroll()
        .themedBackground()
        .pageChrome("Materiale didattico", style: .inline)
        .localSearchable(text: $search, prompt: Self.searchPrompt)
        .quickLookPreview($previewURL)
        .sheet(item: $textItem) { item in
            NavigationStack {
                ScrollView {
                    Text(item.text)
                        .font(.m3(15))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .sheetChrome(item.title, trailing: [.confirm("Fine") { textItem = nil }])
            }
            .m3Sheet()
            .presentationDetents([.medium, .large])
        }
        .task {
            if model.didactics.isEmpty {
                loading = true
                error = await model.loadDidactics()
                loading = false
            }
        }
        .refreshable { error = await model.loadDidactics() }
    }

    @ViewBuilder
    private var teacherChips: some View {
        FilterChip(title: "Tutti i docenti", isSelected: teacherFilter == nil) { teacherFilter = nil }
        ForEach(model.didactics) { teacher in
            FilterChip(title: teacher.name, isSelected: teacherFilter == teacher.id) {
                teacherFilter = teacherFilter == teacher.id ? nil : teacher.id
            }
        }
    }

    /// Le cartelle di ogni docente, sotto il suo nome.
    @ViewBuilder
    private var teacherGroups: some View {
        ForEach(teachers) { teacher in
            let list = folders(of: teacher)
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(String(teacher.name.prefix(1)))
                            .font(.numeral(16))
                            .foregroundStyle(Theme.surface)
                            .frame(width: 36, height: 36)
                            .background(Theme.subjectColor(StableID.make(teacher.id)),
                                        in: .rect(cornerRadius: Theme.radii.m, style: .continuous))
                        Text(teacher.name)
                            .font(.m3(18, weight: 550))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.leading, 4)

                    // Le cartelle di un docente formano una lista segmentata.
                    ListGroup {
                        ForEach(list) { folder in
                            folderCard(folder, teacher: teacher)
                        }
                    }
                }
            }
        }
    }

    private func folderCard(_ folder: DidacticFolder, teacher: DidacticTeacher) -> some View {
        let key = "\(teacher.id)-\(folder.id)"
        let isExpanded = expandedFolders.contains(key) || !search.isEmpty
        let contents = folder.contents.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || folder.name.localizedCaseInsensitiveContains(search)
        }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.spatial) {
                    if expandedFolders.contains(key) { expandedFolders.remove(key) } else { expandedFolders.insert(key) }
                }
            } label: {
                HStack(spacing: 12) {
                    Icon(isExpanded ? "folderFill" : "folder")
                        .foregroundStyle(Theme.subject(3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folder.name)
                            .font(.m3(15, weight: 600))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Text("\(folder.contents.count) elementi\(folder.lastShare.map { " · \($0.shortDayWithYear)" } ?? "")")
                            .font(.m3(12))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer()
                    Chevron(collapsed: !isExpanded, rotateUp: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(HeaderButtonStyle())

            CollapsibleContent(isExpanded: isExpanded) {
                VStack(spacing: 0) {
                    ForEach(contents) { content in
                        M3Divider(inset: 56)
                        Button {
                            Task { await open(content) }
                        } label: {
                            HStack(spacing: 12) {
                                Icon(content.icon)
                                    .foregroundStyle(Theme.primary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(content.name)
                                        .font(.m3(15))
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading)
                                    if let date = content.sharedAt {
                                        Text(date.shortDayWithYear)
                                            .font(.m3(12))
                                            .foregroundStyle(Theme.secondaryInk)
                                    }
                                }
                                Spacer()
                                if openingContent == content.id {
                                    InlineProgress()
                                } else {
                                    Icon(content.kind == .link ? "externalLink" : "download")
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.listRow)
                    }
                }
            }
        }
    }

    private func open(_ content: DidacticContent) async {
        openingContent = content.id
        defer { openingContent = nil }
        do {
            let item = try await model.openDidacticContent(content)
            switch item {
            case .file(let url): previewURL = url
            case .link(let url): openURL(url)
            case .text(let text): textItem = TextItem(title: content.name, text: text)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
