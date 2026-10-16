import SwiftUI

// MARK: - Intestazioni

/// Intestazione di una sezione (22 punti, come `.section-header` nella versione web).
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.m3(22, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.m3(14))
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

/// Occhiello: etichetta breve sopra a un contenuto (title-small nei colori del tema).
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.secondaryInk

    var body: some View {
        Text(text)
            .font(.m3(14, weight: 650))
            .tracking(0.1)
            .foregroundStyle(color)
    }
}

/// Logo di BCW: la scritta in Google Sans Flex e la linea nel colore del marchio.
struct BCWLogo: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.42) {
            Text("BCW")
                .font(.m3(size, weight: 800, rounded: true))
                .tracking(-size * 0.01)
                .foregroundStyle(Theme.ink)
            Capsule(style: .continuous)
                .fill(Theme.brand)
                .frame(width: size * 1.1, height: size * 0.15)
                .alignmentGuide(.firstTextBaseline) { $0.height + size * 0.2 }
        }
        .fixedSize()
        .accessibilityElement()
        .accessibilityLabel("BCW")
    }
}

// MARK: - Voti

/// Voto in una forma di M3 Expressive: i voti che fanno media stanno in un "biscotto" a nove
/// lobi nel colore del loro esito, gli altri in un cerchio.
struct GradeBadge: View {
    let grade: Grade
    var size: CGFloat = 48

    var body: some View {
        let tone = Theme.tone(grade)
        let counts = grade.countsTowardAverage
        let text = grade.displayValue
        let factor: CGFloat = text.count > 3 ? 0.27 : (text.count > 2 ? 0.32 : 0.4)
        Shaped(shape: counts ? .cookie9Sided : .circle,
               fill: counts ? tone.container : Theme.surfaceContainerHighest, size: size) {
            Text(text)
                .font(.m3(size * factor, weight: 700, rounded: true).monospacedDigit())
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(counts ? tone.onContainer : Theme.onSurfaceVariant)
                .strikethrough(grade.canceled)
                .padding(4)
        }
        .accessibilityElement()
        .accessibilityLabel("Voto \(grade.displayValue)")
    }
}

/// Anello che si riempie in proporzione alla media (su 10): un indicatore circolare di M3
/// Expressive, con la parte piena ondulata e uno spazio prima della traccia.
struct AverageRing: View {
    let value: Double?
    var size: CGFloat = 120
    var lineWidth: CGFloat = 10
    var showsLabel = true

    var body: some View {
        let tone = Theme.tone(value: value)
        let progress = min(1, max(0, (value ?? 0) / 10))
        ZStack {
            RingShape(progress: progress, lineWidth: lineWidth, track: true, wavy: false)
                .stroke(tone.container, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            RingShape(progress: progress, lineWidth: lineWidth, track: false, wavy: size >= 60)
                .stroke(tone.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            if showsLabel {
                Text(GradeFormat.average(value))
                    .font(.numeral(size * 0.25, weight: 700))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.spatialSlow, value: progress)
        .accessibilityElement()
        .accessibilityLabel("Media \(GradeFormat.average(value))")
    }
}

/// Arco dell'anello della media: la parte piena (ondulata) o la traccia dopo lo spazio.
private struct RingShape: Shape {
    var progress: Double
    let lineWidth: CGFloat
    let track: Bool
    let wavy: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let r = (size - lineWidth) / 2 - (size >= 60 ? 3 : 0)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = -Double.pi / 2
        let gap = Double(lineWidth * 1.1 + 4) / Double(r)
        let end = start + progress * 2 * .pi
        var path = Path()
        if track {
            guard progress < 0.999 else { return path }
            let from = progress > 0 ? end + gap : start
            let to = start + 2 * .pi - (progress > 0 ? gap : 0)
            guard to > from else { return path }
            path.addArc(center: center, radius: r, startAngle: .radians(from), endAngle: .radians(to), clockwise: false)
            return path
        }
        guard progress > 0 else { return path }
        let to = progress >= 0.999 ? start + 2 * .pi : end
        if !wavy {
            path.addArc(center: center, radius: r, startAngle: .radians(start), endAngle: .radians(to), clockwise: false)
            return path
        }
        // L'onda si appiattisce agli estremi, così l'arco comincia e finisce sul cerchio.
        let amplitude = min(3, Double(size) / 40)
        let wavelength = max(16, Double(size) / 4)
        let length = (to - start) * Double(r)
        let steps = max(8, Int(ceil(length / 2)))
        for i in 0...steps {
            let t = start + (to - start) * Double(i) / Double(steps)
            let s = (t - start) * Double(r)
            let fade = min(1, s / wavelength, (length - s) / wavelength)
            let rr = Double(r) + amplitude * fade * sin(s / wavelength * 2 * .pi)
            let point = CGPoint(x: center.x + rr * cos(t), y: center.y + rr * sin(t))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Barra di avanzamento lineare e ondulata, con lo spazio e il punto finale di M3.
struct WavyProgress: View {
    let value: Double
    let total: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = min(1, max(0, total > 0 ? value / total : 0))
        GeometryReader { proxy in
            let active = proxy.size.width * p
            HStack(spacing: 6) {
                if p > 0 {
                    TimelineView(.animation(paused: reduceMotion || ThemeStore.shared.motion == .reduced)) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        WaveShape(phase: phase, amplitude: 2.75, wavelength: 20)
                            .stroke(Theme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                    .frame(width: max(0, active - 3), height: 12)
                }
                if p < 1 {
                    Capsule()
                        .fill(Theme.secondaryContainer)
                        .frame(height: 4)
                        .overlay(alignment: .trailing) {
                            Circle().fill(Theme.primary).frame(width: 4, height: 4)
                        }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityValue("\(Int(p * 100))%")
    }
}

/// Onda orizzontale (avanzamento e separatori degli intervalli).
struct WaveShape: Shape {
    var phase: Double = 0
    var amplitude: CGFloat
    var wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        let step: CGFloat = 1
        var x: CGFloat = 0
        let start = rect.minX + 2
        let end = rect.maxX - 2
        guard end > start else { return path }
        x = start
        path.move(to: CGPoint(x: x, y: mid - amplitude * sin((x / wavelength - phase) * 2 * .pi)))
        while x < end {
            x = min(end, x + step)
            path.addLine(to: CGPoint(x: x, y: mid - amplitude * sin((x / wavelength - phase) * 2 * .pi)))
        }
        return path
    }
}

/// Linea ondulata orizzontale (separatori degli intervalli dell'orario).
struct WavyRule: View {
    var color: Color = Theme.onSurfaceVariant.opacity(0.55)

    var body: some View {
        WaveShape(amplitude: 1.8, wavelength: 11)
            .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            .frame(minWidth: 12, maxWidth: .infinity)
            .frame(height: 6)
    }
}

// MARK: - Materie

/// Nome di una materia con il rombo del suo colore.
struct SubjectTag: View {
    let name: String
    let id: Int?
    var font: Font = .m3(15, weight: 600)

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.subjectColor(id))
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
            Text(name)
                .font(font)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
    }
}

// MARK: - Sezioni comprimibili

/// Contenuto di una sezione comprimibile. Chiudendo, il contenuto scorre verso l'alto
/// restando ritagliato nell'area che occupa da aperto (con una sfumatura sul bordo
/// superiore), così non invade l'intestazione né il resto della pagina.
struct CollapsibleContent<Content: View>: View {
    let isExpanded: Bool
    /// Spazio tra intestazione e contenuto: fa parte dell'area che si comprime.
    var spacing: CGFloat = 0
    /// Altezza massima della sfumatura sul bordo superiore durante l'animazione.
    var fade: CGFloat = 24
    @ViewBuilder let content: () -> Content
    @State private var height: CGFloat = 0

    var body: some View {
        CollapseBody(progress: isExpanded ? 1 : 0, height: height, fade: fade, spacing: spacing,
                     onHeightChange: { height = $0 }, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
    }
}

/// Anima apertura e chiusura: `progress` va da 0 (chiusa) a 1 (aperta).
/// È una vista (non un modificatore) per costruire il contenuto solo quando serve: da chiusa,
/// ad animazione finita, il contenuto non viene né costruito né disegnato. Così non costa nulla
/// (le sezioni chiuse possono essere molte, es. i voti) e, se cambia mentre è nascosto (es. i
/// giorni successivi quando si sceglie un altro giorno), le sue animazioni non si intravedono
/// sotto l'intestazione, dove la maschera si allarga per le ombre. L'altezza misurata resta e
/// serve alla prossima apertura.
private struct CollapseBody<Content: View>: View, Animatable {
    var progress: CGFloat
    let height: CGFloat
    let fade: CGFloat
    let spacing: CGFloat
    let onHeightChange: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        // Le molle con un po' di rimbalzo superano l'1: senza limite il contenuto finirebbe
        // troppo in basso e poi tornerebbe al suo posto con uno scatto.
        let clamped = min(max(progress, 0), 1)
        let hidden = (1 - clamped) * height
        // La sfumatura non supera mai la parte già nascosta: da aperta il bordo è netto
        // e nessun contenuto al suo posto viene attenuato.
        let gradient = min(fade, hidden)
        // Finché il contenuto non è stato misurato (sezione appena creata) non lo si
        // vincola, così da aperta non parte da altezza zero.
        let frameHeight: CGFloat? = height == 0 && clamped == 1 ? nil : max(0, height - hidden)
        if clamped > 0 {
            content()
                .padding(.top, spacing)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
                .offset(y: -hidden)
                .frame(height: frameHeight, alignment: .top)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: gradient)
                        Rectangle()
                    }
                    // Il ritaglio serve solo sul bordo superiore: ai lati e in basso
                    // la maschera si allarga per non tagliare le ombre.
                    .padding([.horizontal, .bottom], -40)
                }
                // Compare e scompare senza transizioni proprie: l'animazione è già quella di apertura.
                .transition(.identity)
        } else {
            Color.clear.frame(height: 0)
                .transition(.identity)
        }
    }
}

// MARK: - Riquadri

/// Riquadro con un numero (assenze, ritardi, medie…): l'icona sta in una forma.
struct StatTile: View {
    let title: String
    let value: String
    var icon: String
    var tint: Color = Theme.accent
    var shape: MaterialShapeName = .cookie4Sided
    /// Riempie l'altezza disponibile (su macOS, accanto alla card del profilo).
    var fillsHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Shaped(shape: shape, fill: tint.mix(Theme.surfaceContainerHigh, 0.18), size: 44) {
                Icon(icon, size: 22)
                    .foregroundStyle(tint)
            }
            .padding(.bottom, 8)
            Text(value)
                .font(.numeral(28))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(title)
                .font(.m3(13, weight: 550))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .card()
    }
}

/// Icona in un quadrato arrotondato tinto (voci delle liste, sezioni di Tu).
struct IconBadge: View {
    let icon: String
    var tint: Color = Theme.accent
    var size: CGFloat = 40

    var body: some View {
        Icon(icon, size: size * 0.58)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: size * 0.34, style: .continuous))
    }
}

/// Iniziali in una forma (biscotto, cerchio…), nel colore indicato.
struct Avatar: View {
    let initials: String
    var size: CGFloat = 64
    var shape: MaterialShapeName = .circle
    var tint: Color?
    var rotation: Angle = .zero

    var body: some View {
        Shaped(shape: shape, fill: tint.map { $0.mix(Theme.surfaceContainerHighest, 0.28) } ?? Theme.primaryContainer,
               size: size, rotation: rotation) {
            Text(initials)
                .font(.m3(size * 0.4, weight: 650, rounded: true))
                .foregroundStyle(tint == nil ? Theme.onPrimaryContainer : Theme.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(size * 0.12)
        }
    }
}

// MARK: - Righe comuni

struct AbsenceRow: View {
    let absence: AbsenceEvent
    /// Mostra il motivo della giustificazione sotto il dettaglio.
    var showsReason = false

    var body: some View {
        HStack(spacing: 14) {
            Shaped(shape: .cookie6Sided, fill: tone.container, size: 40) {
                Text(absence.kind.letter)
                    .font(.numeral(15))
                    .foregroundStyle(tone.onContainer)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(absence.kind.title)
                    .font(.m3(16, weight: 550))
                    .foregroundStyle(Theme.ink)
                Text(absence.detail)
                    .font(.m3(14))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if showsReason, let reason = absence.justificationReason {
                    Text(reason)
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            // Il testo ha la precedenza: se non c'è spazio è la pillola ad abbreviarsi.
            .layoutPriority(1)
            Spacer(minLength: 4)
            if absence.isJustified {
                Icon("checkSealFill")
                    .foregroundStyle(Theme.good)
                    .accessibilityLabel("Giustificata")
            } else {
                Pill(text: "Da giustificare", short: "Da giust.", color: Theme.poor)
            }
        }
    }

    private var tone: Theme.Tone {
        switch absence.kind {
        case .absence: .poor
        case .late, .shortLate: .fair
        case .earlyExit: .neutral
        }
    }
}

struct LessonRow: View {
    let lesson: Lesson

    var body: some View {
        let tint = Theme.subjectColor(lesson.subjectId)
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text("\(lesson.hour)")
                    .font(.numeral(20))
                Text("ORA")
                    .font(.m3(10, weight: 600))
                    .tracking(0.6)
            }
            .foregroundStyle(tint)
            .frame(width: 44, height: 48)
            .background(tint.opacity(0.16), in: .rect(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    SubjectTag(name: lesson.subjectName, id: lesson.subjectId)
                    if lesson.duration > 1 {
                        Text("\(Int(lesson.duration)) ore")
                            .font(.m3(12))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                if !lesson.topic.isEmpty {
                    Text(lesson.topic)
                        .font(.m3(15))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let meta = [lesson.type, lesson.authorName].filter { !$0.isEmpty }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Stati

/// Avviso di stato (es. dati non aggiornati), nel contenitore "sufficiente".
struct StatusBanner: View {
    let message: String
    var icon = "wifiOff"

    var body: some View {
        HStack(spacing: 12) {
            Icon(icon, size: 20)
            Text(message)
                .font(.m3(14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.onFairContainer)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fairContainer, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
    }
}

struct LoadingCard: View {
    var text = "Caricamento…"

    var body: some View {
        HStack(spacing: 14) {
            LoadingIndicator(size: 36)
            Text(text)
                .font(.m3(14))
                .foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .card()
    }
}

/// Indicatore di caricamento dentro righe e pulsanti.
struct InlineProgress: View {
    var tint: Color?
    var size: CGFloat = 22

    var body: some View {
        LoadingIndicator(size: size, color: tint)
    }
}

/// Riga "chiave: valore" per le schede di dettaglio.
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(Theme.secondaryInk)
            Spacer(minLength: 16)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.m3(14))
    }
}

/// Stato vuoto (al posto di `ContentUnavailableView`): l'icona sta in una forma espressiva.
struct EmptyState<Actions: View>: View {
    let title: String
    let icon: String
    var description: String?
    @ViewBuilder var actions: () -> Actions

    private static var shapes: [MaterialShapeName] {
        [.cookie12Sided, .clover4Leaf, .softBurst, .sunny, .cookie7Sided, .flower, .puffy, .gem]
    }

    var body: some View {
        let hash = title.unicodeScalars.reduce(UInt32(0)) { ($0 &* 31 &+ $1.value) }
        VStack(spacing: 8) {
            Shaped(shape: Self.shapes[Int(hash % UInt32(Self.shapes.count))], fill: Theme.secondaryContainer, size: 88) {
                Icon(icon, size: 40)
                    .foregroundStyle(Theme.onSecondaryContainer)
            }
            .padding(.bottom, 10)
            Text(title)
                .font(.m3(22, weight: 500, rounded: true))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let description, !description.isEmpty {
                Text(description)
                    .font(.m3(14))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                actions()
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: String, icon: String, description: String? = nil) {
        self.title = title
        self.icon = icon
        self.description = description
        self.actions = { EmptyView() }
    }
}

extension EmptyState {
    init(_ title: String, icon: String, description: String? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.icon = icon
        self.description = description
        self.actions = actions
    }
}

/// Contatore con titolo e valore in una riga (per i moduli che usano ancora `Form`).
struct LabeledStepper<Value: Strideable & Comparable>: View {
    let title: String
    let value: String
    @Binding var number: Value
    let range: ClosedRange<Value>
    var step: Value.Stride = 1

    init(_ title: String, value: String, number: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride = 1) {
        self.title = title
        self.value = value
        _number = number
        self.range = range
        self.step = step
    }

    var body: some View {
        StepperRow(title: title, value: $number, range: range, step: step) { _ in value }
    }
}
