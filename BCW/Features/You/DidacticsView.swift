import QuickLook
import SwiftUI

struct DidacticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
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
                    StatusBanner(message: error, symbol: "exclamationmark.triangle")
                }

                if !model.didactics.isEmpty {
                    ChipRow {
                        FilterChip(title: "Tutti i docenti", isSelected: teacherFilter == nil) { teacherFilter = nil }
                        ForEach(model.didactics) { teacher in
                            FilterChip(title: teacher.name, isSelected: teacherFilter == teacher.id) {
                                teacherFilter = teacherFilter == teacher.id ? nil : teacher.id
                            }
                        }
                    }
                }

                if loading && model.didactics.isEmpty {
                    LoadingCard()
                } else if model.didactics.isEmpty {
                    ContentUnavailableView("Nessun materiale", systemImage: "folder",
                                           description: Text("I file condivisi dai docenti appariranno qui."))
                        .padding(.top, 40)
                }

                ForEach(teachers) { teacher in
                    let list = folders(of: teacher)
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(String(teacher.name.prefix(1)))
                                    .font(.numeral(15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.subjectColor(StableID.make(teacher.id)), in: .circle)
                                Text(teacher.name)
                                    .font(.headline)
                                    .foregroundStyle(Theme.ink)
                            }
                            .padding(.leading, 4)

                            CardGrid(minWidth: 360) {
                                ForEach(list) { folder in
                                    folderCard(folder, teacher: teacher)
                                }
                            }
                        }
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, 24)
            .animation(.snappy, value: teacherFilter)
        }
        .themedBackground()
        .screenTitle("Materiale didattico")
        .searchable(text: $search, prompt: "Cerca file o cartelle")
        .quickLookPreview($previewURL)
        .sheet(item: $textItem) { item in
            NavigationStack {
                ScrollView {
                    Text(item.text)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .themedBackground()
                .navigationTitle(item.title)
                .inlineTitleDisplay()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine") { textItem = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .sheetFrame(width: 560, height: 480)
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

    private func folderCard(_ folder: DidacticFolder, teacher: DidacticTeacher) -> some View {
        let key = "\(teacher.id)-\(folder.id)"
        let isExpanded = expandedFolders.contains(key) || !search.isEmpty
        let contents = folder.contents.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || folder.name.localizedCaseInsensitiveContains(search)
        }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if expandedFolders.contains(key) { expandedFolders.remove(key) } else { expandedFolders.insert(key) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Text("\(folder.contents.count) elementi\(folder.lastShare.map { " · \($0.shortDayWithYear)" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryInk)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(HeaderButtonStyle())

            CollapsibleContent(isExpanded: isExpanded) {
                VStack(spacing: 0) {
                    ForEach(contents) { content in
                        Divider().overlay(Theme.separator).padding(.leading, 56)
                        Button {
                            Task { await open(content) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: content.symbol)
                                    .foregroundStyle(Theme.secondaryInk)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(content.name)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading)
                                    if let date = content.sharedAt {
                                        Text(date.shortDayWithYear)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.secondaryInk)
                                    }
                                }
                                Spacer()
                                if openingContent == content.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: content.kind == .link ? "arrow.up.right.square" : "arrow.down.circle")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Theme.surface, in: .rect(cornerRadius: Theme.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Theme.separator.opacity(0.7), lineWidth: 0.5)
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
