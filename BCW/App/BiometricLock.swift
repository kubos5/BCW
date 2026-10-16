import LocalAuthentication
import SwiftUI

/// Blocco opzionale con Face ID / Touch ID / codice del dispositivo.
@Observable
final class BiometricLock {
    private(set) var isLocked = false
    private var isAuthenticating = false

    func lock() { isLocked = true }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        let success = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                        localizedReason: "Sblocca BCW")) ?? false
        if success { withAnimation { isLocked = false } }
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return Platform.isMac ? "password" : "codice"
        }
    }

    static var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.open"
        }
    }
}

struct LockView: View {
    let lock: BiometricLock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                // La forma ruota lentamente, il lucchetto al centro nel verso opposto.
                TimelineView(.animation(paused: reduceMotion || ThemeStore.shared.motion == .reduced)) { timeline in
                    let angle = timeline.date.timeIntervalSinceReferenceDate / 18 * 360
                    Shaped(shape: .cookie12Sided, fill: Theme.primaryContainer, size: 112, rotation: .degrees(angle)) {
                        Icon("lock", size: 44)
                            .foregroundStyle(Theme.onPrimaryContainer)
                    }
                }
                Text("BCW è bloccata")
                    .font(.m3(28, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Label { Text("Sblocca con \(BiometricLock.biometryName)") } icon: { Icon("lockOpen") }
            }
            .buttonStyle(.m3(.filled, size: .m, wide: true))
            .frame(maxWidth: 320)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .ignoresSafeArea()
    }
}
