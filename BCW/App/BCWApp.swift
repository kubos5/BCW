import SwiftUI
import UIKit
import UserNotifications

@main
struct BCWApp: App {
    @State private var model = AppModel()

    init() {
        ProtectedData.restartWhenAvailableIfNeeded()
        Theme.configureAppearance()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        #if DEBUG
        TimetableSelfTest.runIfRequested()
        AppIconGenerator.runIfRequested()
        WidgetSelfTest.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
        }
        // Aggiornamento in background, uno solo per tutta l'app: notifiche delle novità, widget e
        // attività in diretta (`BackgroundRefresh`).
        .backgroundTask(.appRefresh(BackgroundRefresh.taskID)) {
            await BackgroundRefresh.run(model: model)
        }
        // Richiesta dell'attività in diretta di prima della 4.0, se è ancora in sospeso.
        .backgroundTask(.appRefresh(BackgroundRefresh.legacyTaskID)) {
            await BackgroundRefresh.run(model: model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var lock = BiometricLock()
    #if DEBUG
    /// Galleria di prova dei widget (`-BCWWidgetGallery YES`).
    @State private var showsWidgetGallery = UserDefaults.standard.bool(forKey: "BCWWidgetGallery")
    #endif

    var body: some View {
        ZStack {
            switch model.phase {
            case .launching:
                Theme.background.ignoresSafeArea()
            case .signedOut:
                // Sotto l'introduzione niente accesso, che ha forme animate: la fine lo mostra.
                if !Onboarding.shared.isPresented {
                    LoginView()
                        .transition(.opacity)
                }
            case .signedIn:
                Group {
                    MainTabView()
                }
                // Cambiando account tutto scompare e riappare con i nuovi dati (`changeSession`).
                .opacity(model.isChangingSession ? 0 : 1)
                .background(Theme.background.ignoresSafeArea())
                .transition(.opacity)
                .accessibilityHidden(Onboarding.shared.isPresented)
            }

            if lock.isLocked && model.phase == .signedIn {
                LockView(lock: lock)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if Onboarding.shared.isPresented {
                OnboardingView()
                    .zIndex(2)
                    // Compare e sparisce con il cerchio dei colori (`ThemeReveal`).
                    .transition(.identity)
            }
        }
        .animation(Motion.effects, value: model.phase)
        // Note di rilascio dopo un aggiornamento e, nella build GitHub, la versione nuova (`UpdateChecker`).
        .sheet(item: Bindable(UpdateChecker.shared).sheet) { sheet in
            ReleaseSheet(sheet: sheet)
                .environment(model)
                .appTheme()
        }
        // Dopo l'accesso con l'account BCW: abbinare anche gli account del dispositivo?
        .m3Dialog(linkOfferTitle,
                  isPresented: Binding(get: { !model.localAccountsToLink.isEmpty },
                                       set: { if !$0 { model.localAccountsToLink = [] } }),
                  message: linkOfferMessage) {
            let accounts = model.localAccountsToLink
            return [DialogAction.cancel("Non ora"), DialogAction(title: "Abbina", style: .strong) {
                Task { await model.linkLocalAccounts(accounts) }
            }]
        }
        .m3Dialog("Alcuni account non sono stati abbinati",
                  isPresented: Binding(get: { model.linkFailureMessage != nil },
                                       set: { if !$0 { model.linkFailureMessage = nil } }),
                  message: model.linkFailureMessage) {
            [.cancel("OK")]
        }
        // BCW+ (build dell'App Store): dal banner delle Impostazioni, dalla scheda Orario, dall'introduzione
        // e dai widget bloccati. Sopra l'introduzione, che è una sovrapposizione e non un foglio.
        .sheet(isPresented: Bindable(PlusStore.shared).isPaywallPresented) {
            PlusPaywallView()
                .environment(model)
                .appTheme()
        }
        .appTheme()
        .modifier(AppIconStatusReporter())
        .modifier(LiveActivityFailureReporter())
        .overlayHost()
        // Classe della finestra (iPad largo o layout dell'iPhone), anche per menu e dialoghi.
        .modifier(WindowLayoutReader())
        #if DEBUG
        .modifier(FakeWindow())
        #endif
        #if DEBUG
        .fullScreenCover(isPresented: Binding(get: { showsWidgetGallery && model.phase == .signedIn },
                                              set: { showsWidgetGallery = $0 })) {
            WidgetGalleryView()
                .environment(model)
                .appTheme()
        }
        #endif
        .task {
            // La finestra ora esiste: prende il colore d'accento del tema per i componenti di UIKit.
            Theme.applyTint()
            #if DEBUG
            DebugOrientation.applyIfRequested()
            DebugScript.shared.start()
            #endif
            model.bootstrap()
            PlusStore.shared.start()
            #if DEBUG
            // Per le prove: `-BCWPaywall YES` apre la schermata di BCW+ (build dell'App Store).
            if UserDefaults.standard.bool(forKey: "BCWPaywall") { PlusStore.shared.presentPaywall() }
            #endif
            UpdateChecker.shared.launch()
            AppIconController.shared.start()
            if model.preferences.useBiometrics && model.phase == .signedIn {
                lock.lock()
                await lock.unlock()
            }
            await presentReleaseSheetIfNeeded()
        }
        // Finita l'introduzione (mai la prima volta: `UpdateChecker` lo sa da sé) o sbloccata l'app.
        .onChange(of: Onboarding.shared.isPresented) { _, presented in
            if !presented { Task { await presentReleaseSheetIfNeeded() } }
        }
        .onChange(of: lock.isLocked) { _, locked in
            if !locked { Task { await presentReleaseSheetIfNeeded() } }
        }
        // Collegamenti `bcw://` dei widget (scheda e giorno).
        .onOpenURL { model.open($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                NewsNotifications.scheduleBackgroundRefresh(model: model)
                model.widgets.flush()
            }
            if phase == .active {
                AppIconController.shared.sceneBecameActive()
                Task { await presentReleaseSheetIfNeeded() }
                // Un'attività in diretta che iOS non disegna più si riprende solo rifacendola.
                model.liveActivities.sceneBecameActive()
            }
            if model.isCloud {
                // Tornando nell'app arrivano le modifiche degli altri dispositivi; uscendo partono
                // subito quelle in attesa.
                if phase == .active { Task { await model.refreshCloud() } }
                if phase == .background { flushCloudChanges() }
            }
            guard model.preferences.useBiometrics, model.phase == .signedIn else { return }
            if phase == .background { lock.lock() }
            if phase == .active, lock.isLocked { Task { await lock.unlock() } }
        }
    }
}

extension RootView {
    private var linkOfferTitle: String {
        let accounts = model.localAccountsToLink
        if accounts.count == 1, let account = accounts.first { return "Abbinare \(account.name) al tuo account BCW?" }
        return "Abbinare \(accounts.count) account al tuo account BCW?"
    }

    private var linkOfferMessage: String {
        let accounts = model.localAccountsToLink
        let names = accounts.map(\.name).joined(separator: ", ")
        let intro = accounts.count == 1
            ? "Su questo dispositivo c'è un account Classeviva"
            : "Su questo dispositivo ci sono \(accounts.count) account Classeviva"
        return "\(intro) (\(names)). Abbinandoli li ritroverai con il tuo account BCW su ogni dispositivo, insieme al loro orario."
    }

    /// Note di rilascio o versione nuova, con l'app in primo piano e pronta: non sopra l'introduzione, il
    /// blocco con Face ID o l'avvio.
    private func presentReleaseSheetIfNeeded() async {
        guard scenePhase == .active, model.phase != .launching, !Onboarding.shared.isPresented,
              !(lock.isLocked && model.phase == .signedIn) else { return }
        await UpdateChecker.shared.presentIfNeeded(updateAlerts: model.preferences.updateAlerts)
    }

    /// Invia le modifiche in attesa per l'account BCW anche se l'app va in secondo piano.
    private func flushCloudChanges() {
        let task = UIApplication.shared.beginBackgroundTask(withName: "BCW-sync", expirationHandler: nil)
        Task {
            await model.cloudSync.flush()
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}

extension View {
    /// Carattere, colore d'accento e sfondo dell'app (Google Sans Flex e i colori di Material 3).
    func appTheme() -> some View {
        font(.m3(16))
            .tint(Theme.primary)
            .foregroundStyle(Theme.ink)
    }
}
