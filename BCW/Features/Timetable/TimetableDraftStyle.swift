import SwiftUI
import UIKit

// Anteprima dell'orario generato, in stile Material 3 Expressive: finché non si applica, gli eventi
// sono pillole morbide nella loro tinta, con un'onda al posto della barretta e un'onda di luce che
// attraversa la giornata dall'alto in basso. Applicando le forme si assestano con una molla negli
// angoli normali e l'onda si raddrizza; in basso una barra degli strumenti vivace (modalità
// temporanea) con Applica e Scarta.

// MARK: - Onda di luce

/// Riflesso che attraversa un evento dell'anteprima. La fase dipende dalla posizione sullo schermo,
/// così tutti gli eventi insieme sembrano una sola onda che scende lungo la giornata. Lo anima Core
/// Animation, fuori dal thread principale (vedi `MovingWave`).
struct DraftSheen: UIViewRepresentable {
    func makeUIView(context: Context) -> DraftSheenView { DraftSheenView() }
    func updateUIView(_ view: DraftSheenView, context: Context) {
        view.update(isDark: context.environment.colorScheme == .dark,
                    paused: context.environment.accessibilityReduceMotion || ThemeStore.shared.motion == .reduced)
    }
}

final class DraftSheenView: UIView {
    /// Quanto dura un passaggio dell'onda e quanti punti percorre in un secondo.
    private static let period: Double = 3.4
    private static let speed: Double = 420

    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradient: CAGradientLayer { layer as! CAGradientLayer }
    private var paused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.locations = [-0.6, -0.3, 0]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    func update(isDark: Bool, paused: Bool) {
        let light = UIColor.white.withAlphaComponent(isDark ? 0.14 : 0.42)
        gradient.colors = [UIColor.white.withAlphaComponent(0).cgColor, light.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        if paused != self.paused {
            self.paused = paused
            restart()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { restart() }
    }

    private func restart() {
        gradient.removeAnimation(forKey: "sheen")
        guard !paused, window != nil else { return }
        // Più in basso sullo schermo, più tardi: l'onda scende.
        let y = Double(convert(bounds, to: nil).minY)
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.6, -0.3, 0]
        animation.toValue = [1, 1.3, 1.6]
        animation.duration = 1.1
        let group = CAAnimationGroup()
        group.animations = [animation]
        group.duration = Self.period
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        group.timeOffset = (CACurrentMediaTime() - y / Self.speed + Self.period * 1000)
            .truncatingRemainder(dividingBy: Self.period)
        gradient.add(group, forKey: "sheen")
    }
}

// MARK: - Onda al posto della barretta

/// La barretta colorata di un evento dell'anteprima: un'onda verticale, che applicando si raddrizza
/// (`amplitude` a 0, con una molla).
struct DraftWaveBar: View, Animatable {
    var amplitude: CGFloat
    let color: Color

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    var body: some View {
        VerticalWave(amplitude: amplitude)
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}

/// Linea verticale ondulata, centrata nel riquadro.
private struct VerticalWave: Shape {
    var amplitude: CGFloat
    private static let wavelength: CGFloat = 16

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 2
        let height = rect.height - inset * 2
        guard height > 0 else { return path }
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + inset))
        var y: CGFloat = 0
        while y < height {
            y = min(y + 1, height)
            path.addLine(to: CGPoint(x: rect.midX + sin(y / Self.wavelength * 2 * .pi) * amplitude, y: rect.minY + inset + y))
        }
        return path
    }
}

// MARK: - Comparsa a scaglioni

extension AnyTransition {
    /// Un evento dell'anteprima che compare: cresce con una molla, a scaglioni lungo la giornata.
    static func draftBlock(index: Int) -> AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity).animation(Motion.spatial.delay(Double(index) * 0.035)),
                    removal: .opacity.animation(Motion.effects))
    }
}

// MARK: - Intestazione e barra degli strumenti

/// Sopra l'anteprima: da dove viene l'orario, con una forma che ruota lentamente.
struct TimetableDraftHeader: View {
    @Environment(AppModel.self) private var model
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let draft = model.timetable.draft {
            HStack(spacing: 14) {
                ZStack {
                    MaterialShape(.sunny)
                        .fill(Theme.onTertiaryContainer.opacity(0.14))
                        .rotationEffect(.degrees(turning ? 360 : 0))
                    Icon("wand", size: 24)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anteprima dell'orario")
                        .font(.m3(17, weight: 600, rounded: true))
                    Text("\(lessonCount(draft)) lezioni ricavate da \(draft.analyzedDays) giorni di registro (\(draft.from.shortDay) – \(draft.to.shortDay))")
                        .font(.m3(12))
                        .opacity(0.85)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.timetable.draftNeedsFreeAlignment {
                        Text("Orari esatti: applicando, l'orario passa all'allineamento libero.")
                            .font(.m3(12, weight: 600))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.onTertiaryContainer)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.tertiaryContainer, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
            .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            .onAppear {
                guard !reduceMotion, ThemeStore.shared.motion != .reduced else { return }
                withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { turning = true }
            }
        }
    }

    private func lessonCount(_ draft: TimetableDraft) -> Int {
        draft.entries.filter { !$0.isBreak }.count
    }
}

/// Barra degli strumenti vivace dell'anteprima (modalità temporanea, al posto della barra delle
/// schede): rigenera, scarta, applica.
struct TimetableDraftToolbar: View {
    @Environment(AppModel.self) private var model
    let onSettings: () -> Void
    @State private var confirmingApply = false

    var body: some View {
        FloatingToolbar(vibrant: true) {
            ToolbarIconButton("tune", label: "Cambia le impostazioni e rigenera", action: onSettings)
            ToolbarIconButton("trash", label: "Scarta l'anteprima") {
                withAnimation(Motion.spatial) { model.timetable.draft = nil }
            }
            ToolbarSeparator()
            ToolbarTextButton(title: "Applica", icon: "check") {
                if model.timetable.timetable.isEmpty {
                    apply(replacing: true)
                } else {
                    confirmingApply = true
                }
            }
            .padding(.leading, 4)
        }
        .m3Dialog("Hai già un orario", isPresented: $confirmingApply,
                  message: "Sostituendolo, eventi, note, file e verifiche segnate a mano dell'orario attuale verranno eliminati.",
                  stacked: true) {
            [DialogAction(title: "Sostituisci l'orario attuale", style: .destructive) { apply(replacing: true) },
             DialogAction(title: "Aggiungi solo dove è libero") { apply(replacing: false) },
             .cancel()]
        }
    }

    /// Le pillole dell'anteprima si assestano negli angoli normali.
    private func apply(replacing: Bool) {
        Haptics.success()
        withAnimation(Motion.spatialSlow) { model.timetable.applyDraft(replacing: replacing) }
    }
}
