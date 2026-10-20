import SwiftUI
import WidgetKit

// MARK: - Widget "Media"

/// La media generale nell'anello dei Voti (indicatore circolare di M3 Expressive con l'arco
/// ondulato) e la media del periodo in corso.
struct AverageWidgetView: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let family: WidgetFamily
    let palette: WidgetPalette

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: small
            }
        }
        .widgetURL(DeepLink.grades.url)
    }

    private var grades: WidgetSnapshot.Grades? { snapshot.grades }

    @ViewBuilder
    private var small: some View {
        if !snapshot.signedIn {
            WidgetEmptyState(icon: "grades", title: "Apri BCW per accedere", palette: palette, compact: true)
        } else if let grades, grades.average != nil {
            VStack(spacing: 6) {
                ring(grades.average, size: 86, lineWidth: 9)
                VStack(spacing: 1) {
                    Text("Media generale")
                        .font(palette.font(12.5, weight: 600))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    if let period = grades.current, grades.periods.count > 1 {
                        HStack(spacing: 4) {
                            Text(period.name)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(WidgetGradeFormat.average(period.average))
                                .font(palette.numeral(11.5, weight: 700))
                                .foregroundStyle(palette.tone(period.average))
                                .widgetAccentable()
                        }
                        .font(palette.font(11.5, weight: 500))
                        .foregroundStyle(palette.secondaryInk)
                    } else {
                        Text(grades.countingGrades == 1 ? "1 voto" : "\(grades.countingGrades) voti")
                            .font(palette.font(11.5))
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .privacySensitive()
        } else {
            WidgetEmptyState(icon: "graduationCap", title: "Nessun voto",
                             message: "La media comparirà con i primi voti.", palette: palette, compact: true)
        }
    }

    /// Come `AverageRing` dei Voti: la traccia nel contenitore del tono e l'arco ondulato nel tono.
    private func ring(_ value: Double?, size: CGFloat, lineWidth: CGFloat) -> some View {
        let progress = min(1, max(0, (value ?? 0) / 10))
        return ZStack {
            RingShape(progress: progress, lineWidth: lineWidth, track: true, wavy: false)
                .stroke(palette.toneContainer(value), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            RingShape(progress: progress, lineWidth: lineWidth, track: false, wavy: size >= 60)
                .stroke(palette.tone(value), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .widgetAccentable()
            Text(WidgetGradeFormat.average(value))
                .font(palette.numeral(size * 0.25, weight: 700, rounded: true))
                .tracking(-0.5)
                .foregroundStyle(palette.ink)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var circular: some View {
        if let average = grades?.average, snapshot.signedIn {
            Gauge(value: min(10, max(0, average)), in: 0...10) {
                WidgetIcon("grades", size: 12)
            } currentValueLabel: {
                Text(WidgetGradeFormat.average(average, digits: 1))
                    .font(palette.numeral(15, weight: 750, rounded: true))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
            .privacySensitive()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    WidgetIcon("grades", size: 16)
                    Text("–")
                        .font(palette.numeral(15, weight: 700, rounded: true))
                }
            }
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let average = grades?.average, snapshot.signedIn {
            Label {
                Text("Media \(WidgetGradeFormat.average(average))")
            } icon: {
                Image("m.grades")
            }
        } else {
            Text("Media: nessun voto")
        }
    }
}
