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
                    MovingWave(color: Theme.primary, paused: reduceMotion || ThemeStore.shared.motion == .reduced)
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

/// Onda di `WavyProgress` (spessore 4, estremi arrotondati), che scorre di una lunghezza d'onda
/// ogni 1,6 secondi. La disegna un `CAShapeLayer` e la anima Core Animation, fuori dal thread
/// principale: con una `TimelineView(.animation)` SwiftUI aggiornava la vista a ogni fotogramma
/// finché l'onda era visibile (compiti della Dashboard, lezione in corso dell'Orario).
private struct MovingWave: UIViewRepresentable {
    let color: Color
    let paused: Bool
    /// Per ricolorarla cambiando tema chiaro/scuro.
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> MovingWaveView { MovingWaveView() }

    func updateUIView(_ view: MovingWaveView, context: Context) {
        view.update(color: UIColor(cgColor: color.resolve(in: context.environment).cgColor), paused: paused)
    }
}

final class MovingWaveView: UIView {
    static let amplitude: CGFloat = 2.75
    static let wavelength: CGFloat = 20
    static let period: Double = 1.6
    /// Fotogrammi chiave per periodo: tra uno e l'altro Core Animation interpola i punti (scarto
    /// sotto il trentesimo di punto rispetto alla sinusoide).
    private static let steps = 24

    override class var layerClass: AnyClass { CAShapeLayer.self }
    private var shape: CAShapeLayer { layer as! CAShapeLayer }
    private var paused = false
    private var builtSize: CGSize?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        shape.fillColor = nil
        shape.lineWidth = 4
        shape.lineCap = .round
        shape.lineJoin = .round
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    func update(color: UIColor, paused: Bool) {
        shape.strokeColor = color.cgColor
        if paused != self.paused {
            self.paused = paused
            builtSize = nil
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if builtSize != bounds.size || (!paused && shape.animation(forKey: "wave") == nil) { rebuild() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Animazioni tolte da UIKit (es. fuori dalla finestra): si rimettono.
        if window != nil, !paused, shape.animation(forKey: "wave") == nil { setNeedsLayout() }
    }

    /// La fase segue l'orologio, come la `TimelineView` di prima: più onde restano allineate.
    private func rebuild() {
        let rect = bounds
        builtSize = rect.size
        shape.removeAnimation(forKey: "wave")
        let now = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
        shape.path = Self.path(in: rect, phase: now / Self.period)
        guard !paused, rect.width > 4 else { return }
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = (0...Self.steps).map { Self.path(in: rect, phase: Double($0) / Double(Self.steps)) }
        animation.calculationMode = .linear
        animation.duration = Self.period
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = shape.convertTime(CACurrentMediaTime(), from: nil) - now
        shape.add(animation, forKey: "wave")
    }

    private static func path(in rect: CGRect, phase: Double) -> CGPath {
        WaveShape(phase: phase, amplitude: amplitude, wavelength: wavelength).path(in: rect).cgPath
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

/// Contenuto di una sezione comprimibile, con l'espansione di Material 3: il contenitore si
/// allunga e si accorcia con la molla spaziale (dentro `withAnimation`), il contenuto compare in
/// dissolvenza mentre si apre e svanisce in fretta chiudendo; resta ritagliato dal contenitore.
/// Da chiusa il contenuto non viene costruito.
struct CollapsibleContent<Content: View>: View {
    let isExpanded: Bool
    /// Spazio tra intestazione e contenuto: fa parte dell'area che si comprime.
    var spacing: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                content()
                    .padding(.top, spacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.expand)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

// MARK: - Riquadri

/// Riquadro con un numero (assenze, ritardi, medie…): l'icona sta in una forma. In una griglia
/// collegata (`corners`) solo l'angolo verso l'esterno è ampio, gli altri sono piccoli.
struct StatTile: View {
    let title: String
    let value: String
    var icon: String
    var tint: Color = Theme.accent
    var shape: MaterialShapeName = .cookie4Sided
    /// Riempie l'altezza disponibile.
    var fillsHeight = false
    /// Angolo ampio in una griglia collegata (gli altri piccoli): un angolo, oppure un lato
    /// (`.leading`, `.trailing`) in una riga collegata; `.center` tutti piccoli. Senza, tutti ampi.
    var corners: UnitPoint?
    /// Icona sopra il numero (riquadri stretti, es. tre per riga).
    var vertical = false

    var body: some View {
        if vertical {
            VStack(alignment: .leading, spacing: 10) {
                Shaped(shape: shape, fill: tint.mix(Theme.surfaceContainerHigh, 0.18), size: 40) {
                    Icon(icon, size: 20)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 0) {
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
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .leading)
            .background(Theme.card, in: tileShape)
            .contentShape(tileShape)
        } else {
            horizontal
        }
    }

    private var horizontal: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.numeral(30))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(title)
                    .font(.m3(13, weight: 550))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Shaped(shape: shape, fill: tint.mix(Theme.surfaceContainerHigh, 0.18), size: 40) {
                Icon(icon, size: 20)
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.card, in: tileShape)
        .contentShape(tileShape)
    }

    private var tileShape: UnevenRoundedRectangle {
        let wide = Theme.radii.li
        guard let corners else {
            return UnevenRoundedRectangle(cornerRadii: .init(topLeading: wide, bottomLeading: wide,
                                                             bottomTrailing: wide, topTrailing: wide), style: .continuous)
        }
        let small = Theme.radii.xs
        func radius(_ corner: UnitPoint, _ side: UnitPoint) -> CGFloat { corners == corner || corners == side ? wide : small }
        return UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: radius(.topLeading, .leading),
            bottomLeading: radius(.bottomLeading, .leading),
            bottomTrailing: radius(.bottomTrailing, .trailing),
            topTrailing: radius(.topTrailing, .trailing)), style: .continuous)
    }
}

/// Icona in un cerchio tinto (voci delle liste, sezioni di Tu), come le liste di M3 Expressive.
struct IconBadge: View {
    let icon: String
    var tint: Color = Theme.accent
    var size: CGFloat = 40

    var body: some View {
        Icon(icon, size: size * 0.58)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: .circle)
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
