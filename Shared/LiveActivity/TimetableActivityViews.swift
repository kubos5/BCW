import SwiftUI
import WidgetKit

// MARK: - Colori e testi

/// Colori dell'attività: i ruoli del tema di BCW per la schermata di blocco (chiara o scura, come
/// il sistema) o per la Dynamic Island (sempre quelli scuri: il fondo è nero).
struct ActivityPalette {
    let roles: TimetableActivityTheme.Roles
    let isDark: Bool
    let rond: CGFloat
    let rondBody: CGFloat

    init(theme: TimetableActivityTheme, dark: Bool) {
        roles = dark ? theme.dark : theme.light
        isDark = dark
        rond = theme.rond
        rondBody = theme.rondBody
    }

    /// Fondo della scheda nella schermata di blocco (contenitore della superficie).
    var background: Color { Color(rgb: roles.container) }
    var ink: Color { Color(rgb: roles.onSurface) }
    var secondary: Color { Color(rgb: roles.onSurfaceVariant) }
    var primary: Color { Color(rgb: roles.primary) }
    /// Pillola della lezione successiva.
    var pill: Color { Color(rgb: roles.containerHigh) }
    /// Testo e icone sopra un colore pieno (materia o primario): la superficie.
    var onTint: Color { Color(rgb: roles.surface) }

    func tint(_ tint: WidgetSnapshot.Tint) -> Color { Color(rgb: isDark ? tint.dark : tint.light) }

    /// Colore in evidenza di una fase: la materia della lezione, il primario nelle pause e alla fine.
    func accent(_ phase: TimetableActivityPhase) -> Color {
        switch phase.kind {
        case .before, .lesson: phase.lesson.map { tint($0.tint) } ?? primary
        case .pause, .finished: primary
        }
    }

    func font(_ size: CGFloat, weight: CGFloat = 400, rounded: Bool = false) -> Font {
        WidgetFonts.font(size: size, weight: weight, rond: rounded ? rond : rondBody)
    }

    func numeral(_ size: CGFloat, weight: CGFloat = 600) -> Font {
        font(size, weight: weight, rounded: true).monospacedDigit()
    }
}

/// Testi di una fase, comuni alla schermata di blocco e alla Dynamic Island espansa.
struct ActivityPhaseText {
    let phase: TimetableActivityPhase
    let lessonCount: Int

    private func time(_ date: Date) -> String { WidgetDates.time(date) }

    /// Etichetta in maiuscoletto sopra il titolo.
    var eyebrow: String {
        switch phase.kind {
        case .before: "Prima lezione"
        case .lesson:
            if phase.next == nil, lessonCount > 1 { "Ultima lezione" }
            else if lessonCount > 1 { "Adesso · \(phase.position) di \(lessonCount)" }
            else { "Adesso" }
        case .pause: "Adesso"
        case .finished: "Oggi"
        }
    }

    /// Etichetta corta per la Dynamic Island espansa: accanto alla fotocamera entrano circa 90
    /// punti ("PRIMA LEZIONE" veniva tagliata, verificato), la posizione va a destra (`ordinal`).
    var shortEyebrow: String {
        switch phase.kind {
        case .before: "Prima ora"
        case .lesson: phase.next == nil && lessonCount > 1 ? "Ultima ora" : "Adesso"
        case .pause: "Adesso"
        case .finished: "Oggi"
        }
    }

    /// "2 di 5" durante una lezione (non l'ultima), se le lezioni sono più di una.
    var ordinal: String? {
        guard phase.kind == .lesson, phase.next != nil, lessonCount > 1 else { return nil }
        return "\(phase.position) di \(lessonCount)"
    }

    var title: String {
        switch phase.kind {
        case .before, .lesson: phase.lesson?.title ?? ""
        case .pause: phase.title ?? "Pausa"
        case .finished: "Lezioni finite"
        }
    }

    /// Aula e docente, o gli orari.
    var detail: String {
        switch phase.kind {
        case .before:
            guard let lesson = phase.lesson else { return "" }
            return (["Alle \(time(lesson.start))"] + [Self.place(lesson)].filter { !$0.isEmpty }).joined(separator: " · ")
        case .lesson:
            guard let lesson = phase.lesson else { return "" }
            let parts = [lesson.room, lesson.teacher].filter { !$0.isEmpty }
            return parts.isEmpty ? "\(time(lesson.start))–\(time(lesson.end))" : parts.joined(separator: " · ")
        case .pause: return "Fino alle \(time(phase.end))"
        case .finished: return "L'ultima è finita alle \(time(phase.start))"
        }
    }

    /// Accanto al conto alla rovescia: "tra" (all'inizio) o "ancora" (alla fine).
    var timerLabel: String? {
        switch phase.kind {
        case .before: "tra"
        case .lesson, .pause: "ancora"
        case .finished: nil
        }
    }

    var showsBar: Bool { phase.kind == .lesson || phase.kind == .pause }

    /// La lezione della pillola in fondo: dopo quella in evidenza, o quella che segue la pausa.
    var pillLesson: TimetableActivityLesson? {
        switch phase.kind {
        case .before, .lesson: phase.next
        case .pause: phase.lesson
        case .finished: nil
        }
    }

    /// "Poi alle 09:00 · Italiano" (nelle pause anche l'aula, dove andare): l'ora prima della
    /// materia, che se è lunga viene tagliata.
    var pill: String? {
        guard let lesson = pillLesson else { return nil }
        var text = "Poi alle \(time(lesson.start)) · \(lesson.title)"
        if phase.kind == .pause, !lesson.room.isEmpty { text += " · \(lesson.room)" }
        return text
    }

    /// Con un'ora o più alla fine della fase, al posto del conto alla rovescia l'ora d'arrivo
    /// ("alle 08:00", "fino alle 10:00"): "2:10:--" toglieva spazio all'aula e al docente.
    func longWait(now: Date = Date()) -> (label: String, time: String)? {
        guard phase.kind != .finished, phase.end.timeIntervalSince(now) >= 3600 else { return nil }
        return (phase.kind == .before ? "alle" : "fino alle", time(phase.end))
    }

    /// Aula, o docente.
    static func place(_ lesson: TimetableActivityLesson) -> String {
        lesson.room.isEmpty ? lesson.teacher : lesson.room
    }

    /// Sigla della materia nella forma: una lettera, o due ("Ma", "EF").
    static func initials(_ title: String, max: Int) -> String {
        let words: [String] = title.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 2 }
        if max >= 2, words.count >= 2 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        let letters = (words.first ?? title).filter(\.isLetter)
        guard let first = letters.first else { return "" }
        return max >= 2 ? first.uppercased() + String(letters.dropFirst().prefix(1)).lowercased() : first.uppercased()
    }
}

// MARK: - Elementi

/// La forma di M3 Expressive della fase: la sigla della materia nel suo colore (biscotto durante la
/// lezione, sole prima dell'inizio), la tazza nelle pause, la spunta alla fine.
struct ActivityPhaseShape: View {
    let phase: TimetableActivityPhase
    let palette: ActivityPalette
    let size: CGFloat
    var letters = 2

    var body: some View {
        ZStack {
            MaterialShape(shape)
                .fill(palette.accent(phase))
            switch phase.kind {
            case .before, .lesson:
                Text(ActivityPhaseText.initials(phase.lesson?.title ?? "", max: letters))
                    .font(palette.font(size * (letters >= 2 ? 0.38 : 0.5), weight: 700, rounded: true))
                    .foregroundStyle(palette.onTint)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(size * 0.12)
            case .pause:
                WidgetIcon("coffeeFill", size: size * 0.5)
                    .foregroundStyle(palette.onTint)
            case .finished:
                WidgetIcon("checkCircleFill", size: size * 0.56)
                    .foregroundStyle(palette.onTint)
            }
        }
        .frame(width: size, height: size)
    }

    private var shape: MaterialShapeName {
        switch phase.kind {
        case .before: .sunny
        case .lesson: .cookie12Sided
        case .pause: .cookie9Sided
        case .finished: .circle
        }
    }
}

/// Conto alla rovescia alla fine della fase, largo quanto serve (`Text(timerInterval:)` prende
/// tutto lo spazio che gli si dà).
struct ActivityTimer: View {
    let phase: TimetableActivityPhase
    let font: Font
    let color: Color
    /// Larghezza di una cifra, per riservare lo spazio di "00:00" o "0:00:00".
    let digitWidth: CGFloat

    var body: some View {
        let now = Date()
        // Prima dell'inizio della fase (avvio a mano molto presto) conta comunque fino alla fine.
        let interval = min(now, phase.start)...max(now, phase.end)
        let hours = phase.end.timeIntervalSince(now) >= 3600
        Text(timerInterval: interval, countsDown: true)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .frame(width: digitWidth * (hours ? 7.6 : 5.6), alignment: .trailing)
    }
}

/// "tra"/"ancora" e il conto alla rovescia, o l'ora d'arrivo se manca più di un'ora.
struct ActivityTimerColumn: View {
    let text: ActivityPhaseText
    let palette: ActivityPalette
    let color: Color
    /// Corpo delle cifre (più piccolo nella Dynamic Island, dove l'altezza è poca).
    var size: CGFloat = 24

    var body: some View {
        if let label = text.timerLabel {
            let long = text.longWait()
            VStack(alignment: .trailing, spacing: 0) {
                Text(long?.label ?? label)
                    .font(palette.font(size / 2, weight: 550))
                    .foregroundStyle(palette.secondary)
                if let long {
                    Text(long.time)
                        .font(palette.numeral(size, weight: 650))
                        .foregroundStyle(color)
                } else {
                    ActivityTimer(phase: text.phase, font: palette.numeral(size, weight: 650), color: color,
                                  digitWidth: size * 0.585)
                }
            }
        }
    }
}

/// Barra di avanzamento della fase con gli orari di inizio e fine ai lati.
struct ActivityProgressRow: View {
    let phase: TimetableActivityPhase
    let palette: ActivityPalette
    var timeColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(WidgetDates.time(phase.start))
            ProgressView(timerInterval: phase.interval, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(palette.accent(phase))
            Text(WidgetDates.time(phase.end))
        }
        .font(palette.numeral(12, weight: 550))
        .foregroundStyle(timeColor)
    }
}

/// Pillola con la lezione successiva (icona della verifica se c'è).
struct ActivityNextPill: View {
    let text: String
    let lesson: TimetableActivityLesson
    let palette: ActivityPalette
    let background: Color
    var height: CGFloat = 26

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(palette.tint(lesson.tint))
                .frame(width: 8, height: 8)
            Text(text)
                .font(palette.font(13, weight: 600))
                .lineLimit(1)
            if lesson.isTest {
                WidgetIcon("test", size: 14)
                    .accessibilityLabel("Verifica")
            }
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(background, in: .capsule)
    }
}

/// Chip "Verifica" accanto all'etichetta.
struct ActivityTestChip: View {
    let palette: ActivityPalette
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            WidgetIcon("test", size: 11)
            Text("Verifica")
                .font(palette.font(11, weight: 700))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .frame(height: 17)
        .background(color.opacity(0.16), in: .capsule)
    }
}

// MARK: - Schermata di blocco

/// Schermata di blocco e banner: una scheda di Material sul contenitore della superficie (chiaro o
/// scuro come la schermata di blocco), con il colore della materia come accento.
struct TimetableActivityLockView: View {
    let state: TimetableActivityState
    let isStale: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = ActivityPalette(theme: state.theme, dark: colorScheme == .dark)
        Group {
            if let phase = state.phase(isStale: isStale) {
                content(phase, palette: palette)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(palette.background)
        .activitySystemActionForegroundColor(palette.secondary)
    }

    private func content(_ phase: TimetableActivityPhase, palette: ActivityPalette) -> some View {
        let text = ActivityPhaseText(phase: phase, lessonCount: state.lessonCount)
        let accent = palette.accent(phase)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ActivityPhaseShape(phase: phase, palette: palette, size: 46)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(text.eyebrow.uppercased())
                            .font(palette.font(11.5, weight: 750))
                            .tracking(0.7)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                        if phase.kind != .pause, phase.lesson?.isTest == true {
                            ActivityTestChip(palette: palette, color: accent)
                        }
                    }
                    Text(text.title)
                        .font(palette.font(21, weight: 600, rounded: true))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(text.detail)
                        .font(palette.font(14))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                // Tutto lo spazio tra la forma e il tempo.
                .frame(maxWidth: .infinity, alignment: .leading)
                ActivityTimerColumn(text: text, palette: palette, color: palette.ink)
                    .fixedSize()
            }
            if text.showsBar {
                ActivityProgressRow(phase: phase, palette: palette, timeColor: palette.secondary)
            }
            if let pill = text.pill, let lesson = text.pillLesson {
                ActivityNextPill(text: pill, lesson: lesson, palette: palette, background: palette.pill)
            }
        }
    }
}

// MARK: - Dynamic Island

/// Le viste della Dynamic Island, sul fondo nero: ruoli del tema scuro.
struct TimetableActivityIsland {
    let state: TimetableActivityState
    let isStale: Bool

    var palette: ActivityPalette { ActivityPalette(theme: state.theme, dark: true) }
    var phase: TimetableActivityPhase? { state.phase(isStale: isStale) }
    var accent: Color { phase.map(palette.accent) ?? palette.primary }

    /// Compatta, a sinistra: la forma con la sigla della materia (o la tazza nelle pause).
    @ViewBuilder var compactLeading: some View {
        if let phase {
            ActivityPhaseShape(phase: phase, palette: palette, size: 24, letters: 1)
                .padding(.leading, 2)
        }
    }

    /// Compatta, a destra: il tempo che manca.
    @ViewBuilder var compactTrailing: some View {
        if let phase {
            if phase.kind == .finished {
                WidgetIcon("checkCircleFill", size: 18)
                    .foregroundStyle(accent)
            } else {
                ActivityTimer(phase: phase, font: palette.numeral(15, weight: 650), color: accent, digitWidth: 9)
                    .padding(.trailing, 2)
            }
        }
    }

    /// Minima: anello di avanzamento con la sigla.
    @ViewBuilder var minimal: some View {
        if let phase {
            if phase.kind == .finished {
                WidgetIcon("checkCircleFill", size: 18)
                    .foregroundStyle(accent)
            } else {
                ProgressView(timerInterval: phase.interval, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    minimalLabel(phase)
                }
                .progressViewStyle(.circular)
                .tint(accent)
            }
        }
    }

    @ViewBuilder private func minimalLabel(_ phase: TimetableActivityPhase) -> some View {
        if phase.kind == .pause {
            WidgetIcon("coffeeFill", size: 11)
                .foregroundStyle(accent)
        } else {
            Text(ActivityPhaseText.initials(phase.lesson?.title ?? "", max: 1))
                .font(palette.font(11, weight: 750, rounded: true))
                .foregroundStyle(accent)
        }
    }

    // Espansa. Le regioni ai lati della fotocamera hanno la stessa larghezza e quella al centro
    // sta tra le due: con la forma a sinistra e il tempo a destra i testi restavano stretti e
    // lontani dalla forma. Ai lati vanno quindi solo l'etichetta e la verifica, sotto (regione in
    // basso, larga quanto l'isola) la scheda come nella schermata di blocco.

    /// A sinistra della fotocamera: l'etichetta ("ADESSO · 2 DI 5").
    @ViewBuilder var expandedLeading: some View {
        if let phase {
            Text(ActivityPhaseText(phase: phase, lessonCount: state.lessonCount).shortEyebrow.uppercased())
                .font(palette.font(11, weight: 750))
                .tracking(0.7)
                .foregroundStyle(accent)
                // Niente `minimumScaleFactor` nella Dynamic Island: invece di rimpicciolire, il
                // testo veniva tagliato (verificato).
                .lineLimit(1)
                .padding(.leading, 8)
                .padding(.top, 3)
        }
    }

    /// A destra della fotocamera: il chip della verifica, se c'è, o la posizione della lezione.
    @ViewBuilder var expandedTrailing: some View {
        if let phase {
            if phase.kind != .pause, phase.lesson?.isTest == true {
                ActivityTestChip(palette: palette, color: accent)
                    .padding(.trailing, 8)
                    .padding(.top, 1)
            } else if let ordinal = ActivityPhaseText(phase: phase, lessonCount: state.lessonCount).ordinal {
                Text(ordinal.uppercased())
                    .font(palette.font(11, weight: 750))
                    .tracking(0.7)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .padding(.trailing, 8)
                    .padding(.top, 3)
            }
        }
    }

    @ViewBuilder var expandedBottom: some View {
        if let phase {
            let text = ActivityPhaseText(phase: phase, lessonCount: state.lessonCount)
            // Più compatta della schermata di blocco: l'isola espansa è alta al massimo 160 punti
            // e con le misure di quella la pillola in fondo veniva tagliata (verificato).
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 12) {
                    ActivityPhaseShape(phase: phase, palette: palette, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        // Niente `minimumScaleFactor` nella Dynamic Island: con quello il titolo
                        // veniva tagliato a metà dello spazio ("Matemati…") invece di
                        // rimpicciolire (verificato); così si taglia solo se non entra davvero.
                        Text(text.title)
                            .font(palette.font(18, weight: 600, rounded: true))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(text.detail)
                            .font(palette.font(13))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ActivityTimerColumn(text: text, palette: palette, color: accent, size: 22)
                        .fixedSize()
                }
                if text.showsBar {
                    ActivityProgressRow(phase: phase, palette: palette, timeColor: palette.secondary)
                }
                if let pill = text.pill, let lesson = text.pillLesson {
                    ActivityNextPill(text: pill, lesson: lesson, palette: palette, background: palette.pill, height: 24)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
