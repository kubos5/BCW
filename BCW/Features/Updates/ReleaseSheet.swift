import SwiftUI

/// Foglio delle note di rilascio (dopo un aggiornamento) o della versione nuova su GitHub (build
/// GitHub), con il testo della release di GitHub.
struct ReleaseSheet: View {
    let sheet: UpdateChecker.Sheet
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var shown = false

    private var release: GitHubRelease {
        switch sheet {
        case let .releaseNotes(release), let .update(release): release
        }
    }

    private var isUpdate: Bool {
        if case .update = sheet { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ReleaseNotesText(markdown: release.body ?? "")
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceContainer, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown ? 0 : 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 20)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            actions
        }
        .m3Sheet(size: .form)
        .onAppear { withAnimation(Motion.spatialSlow.delay(0.05)) { shown = true } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Shaped(shape: isUpdate ? .cookie12Sided : .sunny, fill: Theme.primaryContainer, size: 64) {
                Icon(isUpdate ? "systemUpdate" : "newReleases", size: 30)
                    .foregroundStyle(Theme.onPrimaryContainer)
            }
            .scaleEffect(shown ? 1 : 0.5)
            .rotationEffect(.degrees(shown ? 0 : -30))
            VStack(alignment: .leading, spacing: 3) {
                Text(isUpdate ? "È disponibile BCW \(release.version)" : "Novità di BCW \(release.version)")
                    .font(.m3(24, weight: 550, rounded: true))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.m3(13))
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if isUpdate { parts.append("Hai la \(AppVersion(AppVersion.installed))") }
        if let date = release.publishedAt {
            parts.append("Pubblicata il \(date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "it_IT"))))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 4) {
            if isUpdate {
                Button {
                    openURL(release.htmlUrl)
                    dismiss()
                } label: {
                    Label { Text("Scarica da GitHub") } icon: { Icon("download") }
                }
                .buttonStyle(.m3(.filled, size: .m, wide: true))
                HStack(spacing: 4) {
                    Button("Più tardi") {
                        UpdateChecker.shared.snooze(release)
                        dismiss()
                    }
                    .buttonStyle(.m3(.text, size: .s))
                    Button("Non avvisarmi più") {
                        model.preferences.updateAlerts = false
                        dismiss()
                    }
                    .buttonStyle(.m3(.text, size: .s))
                }
                Text("Gli avvisi si riattivano in Impostazioni › Generale.")
                    .font(.m3(11))
                    .foregroundStyle(Theme.onSurfaceVariant)
            } else {
                Button("Continua") { dismiss() }
                    .buttonStyle(.m3(.filled, size: .m, wide: true))
                Button {
                    openURL(release.htmlUrl)
                } label: {
                    Label { Text("Apri su GitHub") } icon: { Icon("externalLink") }
                }
                .buttonStyle(.m3(.text, size: .s))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }
}

/// Il testo di una release di GitHub (Markdown): titoli, elenchi puntati e numerati, citazioni e
/// paragrafi, con grassetto, corsivo, codice e collegamenti dentro le righe. Il primo titolo di primo
/// livello (es. "BCW v3.3.1") si salta: c'è già nell'intestazione del foglio. Immagini e HTML no.
struct ReleaseNotesText: View {
    let markdown: String

    private enum Block: Hashable {
        case heading(Int, String)
        case bullet(Int, String)
        case numbered(String, String)
        case quote(String)
        case paragraph(String)
        case gap
    }

    private var blocks: [Block] {
        var blocks: [Block] = []
        var skippedTitle = false
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if let last = blocks.last, last != .gap { blocks.append(.gap) }
                continue
            }
            if line.hasPrefix("<") || line.hasPrefix("![") || line.hasPrefix("---") { continue }
            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if level == 1 && !skippedTitle && blocks.allSatisfy({ $0 == .gap }) {
                    skippedTitle = true
                    continue
                }
                blocks.append(.heading(level, text))
            } else if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
                blocks.append(.bullet(indent / 2, String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].first == " " {
                blocks.append(.numbered(String(line[..<dot]), String(line[line.index(dot, offsetBy: 2)...])))
            } else if line.hasPrefix(">") {
                blocks.append(.quote(line.drop { $0 == ">" }.trimmingCharacters(in: .whitespaces)))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        while blocks.first == .gap { blocks.removeFirst() }
        while blocks.last == .gap { blocks.removeLast() }
        return blocks
    }

    var body: some View {
        let blocks = blocks
        if blocks.isEmpty {
            Text("Nessuna nota per questa versione.")
                .font(.m3(.bodyM))
                .foregroundStyle(Theme.onSurfaceVariant)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(block)
                }
            }
            .tint(Theme.primary)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(_ block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.m3(level <= 2 ? 20 : (level == 3 ? 17 : 15), weight: 650, rounded: level <= 3))
                .foregroundStyle(level <= 3 ? Theme.primary : Theme.ink)
                .padding(.top, 4)
        case let .bullet(depth, text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                MaterialShape(depth == 0 ? .cookie4Sided : .circle)
                    .fill(depth == 0 ? Theme.primary : Theme.onSurfaceVariant)
                    .frame(width: 7, height: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                Text(inline(text))
                    .font(.m3(.bodyL))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.m3(15, weight: 650))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primary)
                Text(inline(text))
                    .font(.m3(.bodyL))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .quote(text):
            Text(inline(text))
                .font(.m3(.bodyM))
                .foregroundStyle(Theme.onSurfaceVariant)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.outlineVariant).frame(width: 3)
                }
        case let .paragraph(text):
            Text(inline(text))
                .font(.m3(.bodyL))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .gap:
            Color.clear.frame(height: 4)
        }
    }

    /// Grassetto, corsivo, codice e collegamenti di una riga.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
