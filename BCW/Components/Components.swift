import SwiftUI

// MARK: - Intestazioni

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

/// Piccola etichetta maiuscola con spaziatura, usata come occhiello.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.secondaryInk

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

// MARK: - Voti

struct GradeBadge: View {
    let grade: Grade
    var size: CGFloat = 48

    var body: some View {
        let color = Theme.gradeColor(grade)
        ZStack {
            Circle().fill(color.opacity(0.14))
            Circle().strokeBorder(color.opacity(0.9), lineWidth: grade.countsTowardAverage ? 2 : 1.5)
            Text(grade.displayValue)
                .font(.numeral(size * 0.4, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(4)
                .foregroundStyle(color)
                .strikethrough(grade.canceled)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Voto \(grade.displayValue)")
    }
}

/// Anello che si riempie in proporzione alla media (su 10).
struct AverageRing: View {
    let value: Double?
    var size: CGFloat = 120
    var lineWidth: CGFloat = 10
    var showsLabel = true

    var body: some View {
        let color = Theme.gradeColor(value: value)
        ZStack {
            Circle()
                .stroke(Theme.separator.opacity(0.6), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, (value ?? 0) / 10))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: value)
            if showsLabel {
                Text(GradeFormat.average(value))
                    .font(.numeral(size * 0.26, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Media \(GradeFormat.average(value))")
    }
}

// MARK: - Materie e filtri

struct SubjectTag: View {
    let name: String
    let id: Int?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.subjectColor(id))
                .frame(width: 7, height: 7)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
    }
}

struct FilterChip: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Theme.ink)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface))
            }
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.clear : Theme.separator, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.13), in: .circle)
            Text(value)
                .font(.numeral(24, weight: .bold))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .card(padding: 14)
    }
}

// MARK: - Righe comuni

struct IconBadge: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: .rect(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct AbsenceRow: View {
    let absence: AbsenceEvent

    var body: some View {
        HStack(spacing: 12) {
            Text(absence.kind.letter)
                .font(.numeral(15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.13), in: .rect(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(absence.kind.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(absence.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
            if absence.isJustified {
                Label("Giustificata", systemImage: "checkmark.seal.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.good)
            } else {
                Text("Da giustificare")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.poor.opacity(0.13), in: .capsule)
                    .foregroundStyle(Theme.poor)
            }
        }
    }

    private var tint: Color {
        switch absence.kind {
        case .absence: Theme.poor
        case .late, .shortLate: Theme.fair
        case .earlyExit: Theme.neutral
        }
    }
}

struct LessonRow: View {
    let lesson: Lesson

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(lesson.hour)")
                    .font(.numeral(18, weight: .bold))
                    .foregroundStyle(Theme.subjectColor(lesson.subjectId))
                Text("ora")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
            }
            .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    SubjectTag(name: lesson.subjectName, id: lesson.subjectId)
                    Spacer()
                    if lesson.duration > 1 {
                        Text("\(Int(lesson.duration)) ore")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                if !lesson.topic.isEmpty {
                    Text(lesson.topic)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                }
                Text([lesson.type, lesson.authorName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
    }
}

// MARK: - Stati

struct StatusBanner: View {
    let message: String
    var symbol = "wifi.slash"

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Theme.fair.opacity(0.25)), in: .rect(cornerRadius: 16, style: .continuous))
    }
}

struct LoadingCard: View {
    var text = "Caricamento…"

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
                .foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// Riga "chiave: valore" per le schede di dettaglio.
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Theme.secondaryInk)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
