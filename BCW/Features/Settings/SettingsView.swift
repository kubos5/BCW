import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var preferences = model.preferences

        Form {
            Section {
                Picker("Calcolo della media", selection: $preferences.averageMode) {
                    ForEach(AverageMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Usa i pesi dei voti", isOn: $preferences.weightedAverage)
                Stepper(value: $preferences.targetAverage, in: 4...10, step: 0.25) {
                    LabeledContent("Media obiettivo", value: GradeFormat.short(preferences.targetAverage))
                }
            } header: {
                Text("Voti")
            } footer: {
                Text("I voti blu, annullati o \"non fa media\" sono sempre esclusi. I pesi sono quelli impostati dai docenti su Classeviva.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle("Promemoria compiti e verifiche", isOn: $preferences.homeworkReminders)
                    .onChange(of: preferences.homeworkReminders) { _, enabled in
                        Task {
                            if enabled {
                                let granted = await Reminders.requestAuthorization()
                                if !granted {
                                    notificationsDenied = true
                                    model.preferences.homeworkReminders = false
                                }
                            }
                            await model.rescheduleReminders()
                        }
                    }
                if preferences.homeworkReminders {
                    Picker("Orario", selection: $preferences.reminderHour) {
                        ForEach(14...22, id: \.self) { Text("\($0):00").tag($0) }
                    }
                    .onChange(of: preferences.reminderHour) { Task { await model.rescheduleReminders() } }
                }
            } header: {
                Text("Notifiche")
            } footer: {
                Text("Ricevi una notifica la sera prima di ogni compito o verifica. I compiti segnati come fatti vengono saltati.")
            }
            .listRowBackground(Theme.surface)

            Section("Aspetto e sicurezza") {
                Picker("Tema", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Vista della dashboard", selection: $preferences.dashboardMode) {
                    ForEach(DashboardMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                Toggle("Blocca con \(BiometricLock.biometryName)", isOn: $preferences.useBiometrics)
            }
            .listRowBackground(Theme.surface)

            Section("Dati") {
                Button("Aggiorna tutto", systemImage: "arrow.clockwise") {
                    Task { await model.refreshAll() }
                }
                Button("Azzera compiti segnati come fatti", systemImage: "checklist.unchecked") {
                    preferences.completedHomework = []
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Link(destination: URL(string: "https://web.spaggiari.eu")!) {
                    Label("Apri Classeviva sul web", systemImage: "safari")
                }
            } header: {
                Text("Informazioni")
            } footer: {
                Text("BCW (Better ClasseViVa) è un client non ufficiale e non è affiliato a Gruppo Spaggiari Parma S.p.A. Le credenziali sono salvate solo nel Portachiavi di questo dispositivo e inviate esclusivamente ai server di Classeviva.")
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .navigationTitle("Impostazioni")
        .alert("Notifiche disattivate", isPresented: $notificationsDenied) {
            Button("Apri Impostazioni") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Per ricevere i promemoria consenti le notifiche a BCW nelle Impostazioni di iOS.")
        }
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(model.card?.initials ?? String(model.displayName.prefix(1)))
                        .font(.numeral(34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(Theme.accent.gradient, in: .circle)
                    Text(model.displayName)
                        .font(.title2.weight(.semibold))
                    if let classDescription = model.classDescription {
                        Text(classDescription.sentenceCased)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            if let card = model.card {
                Section("Profilo") {
                    LabeledContent("Codice utente", value: card.ident)
                    LabeledContent("Tipo di account", value: card.userTypeDescription)
                    if let birth = card.birthDate {
                        LabeledContent("Data di nascita", value: birth.shortDayWithYear)
                    }
                    if let fiscal = card.fiscalCode?.nilIfEmpty {
                        LabeledContent("Codice fiscale", value: fiscal)
                            .textSelection(.enabled)
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Scuola") {
                    if let school = card.schoolDescription {
                        LabeledContent("Istituto", value: school)
                    }
                    if let city = card.schoolCity?.nilIfEmpty {
                        LabeledContent("Città", value: "\(city.nameCased)\(card.schoolProvince.map { " (\($0))" } ?? "")")
                    }
                    if let code = card.miurSchoolCode?.nilIfEmpty {
                        LabeledContent("Codice meccanografico", value: code)
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                Button("Esci", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmSignOut = true
                }
            } footer: {
                Text(model.isDemo ? "Stai usando la modalità demo." : "Uscendo, le credenziali verranno rimosse da questo dispositivo.")
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Vuoi uscire da BCW?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Esci", role: .destructive) { model.signOut() }
        }
    }
}
