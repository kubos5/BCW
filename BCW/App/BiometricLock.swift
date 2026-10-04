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

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("BCW è bloccata")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Sblocca con \(BiometricLock.biometryName)", systemImage: BiometricLock.biometrySymbol)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .frame(maxWidth: 420)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .background(Theme.background)
        .ignoresSafeArea()
    }
}
