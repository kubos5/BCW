import SwiftUI

/// Allineamento di tutto l'orario. Passando all'automatico con eventi fuori dalle ore e dalle
/// mezz'ore chiede prima conferma, perché quegli eventi verranno spostati (e divisi, se più
/// lunghi di un'ora).
struct TimetableAlignmentPicker: View {
    @Environment(AppModel.self) private var model
    /// Due pulsanti a icona nella barra degli strumenti della modifica, invece della voce con il menu.
    var inToolbar = false
    @State private var confirming = false

    private var store: TimetableStore { model.timetable }

    var body: some View {
        let selection = Binding(get: { store.alignment }, set: request)
        let options = TimetableAlignment.allCases.map { ($0, $0.shortTitle, Optional<String>.none) }
        Group {
            if inToolbar {
                HStack(spacing: 4) {
                    ForEach(TimetableAlignment.allCases, id: \.self) { alignment in
                        ToolbarIconButton(alignment.icon, label: alignment.title,
                                          selected: store.alignment == alignment) {
                            request(alignment)
                        }
                    }
                }
            } else {
                SelectRow("Allineamento", icon: store.alignment.icon, selection: selection, options: options)
            }
        }
        .m3Dialog("Allineare gli eventi?", isPresented: $confirming, message: message) {
            [.cancel(), DialogAction(title: "Allinea", style: .strong) {
                withAnimation(Motion.spatial) { store.setAlignment(.automatic) }
            }]
        }
    }

    private func request(_ alignment: TimetableAlignment) {
        guard alignment != store.alignment else { return }
        if alignment == .automatic && !store.unalignedEntries.isEmpty {
            confirming = true
        } else {
            withAnimation(Motion.spatial) { store.setAlignment(alignment) }
        }
    }

    private var message: String {
        let unaligned = store.unalignedEntries
        let split = unaligned.filter { $0.alignedPieces().count > 1 }.count
        var text = unaligned.count == 1
            ? "Un evento non è allineato alle ore e alle mezz'ore."
            : "\(unaligned.count) eventi non sono allineati alle ore e alle mezz'ore."
        text += " Con l'allineamento automatico inizio e fine verranno spostati all'ora o alla mezz'ora più vicina"
        text += split > 0
            ? " e gli eventi più lunghi di un'ora verranno divisi in eventi da un'ora (o mezz'ora) di seguito, mostrati uniti."
            : "."
        text += " Gli intervalli restano come sono."
        return text
    }
}

/// Istruzioni della modalità di modifica (nel contenitore terziario), sotto la settimana:
/// l'allineamento si sceglie nella barra degli strumenti in basso.
struct TimetableEditBar: View {
    @Environment(AppModel.self) private var model
    /// Settimana intera (iPad largo): gli eventi si spostano anche da un giorno all'altro.
    var multipleDays = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(model.timetable.alignment.icon, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.timetable.alignment.title)
                    .font(.m3(14, weight: 650))
                Text(hint)
                    .font(.m3(12))
                    .opacity(0.85)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Theme.onTertiaryContainer)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tertiaryContainer, in: .rect(cornerRadius: Theme.radii.li, style: .continuous))
        .animation(Motion.effects, value: model.timetable.alignment)
    }

    private var hint: String {
        let alignment = model.timetable.alignment == .automatic
            ? "Scatti di mezz'ora, eventi da 30 minuti o un'ora."
            : "Scatti di 5 minuti; orari esatti dall'evento."
        let gestures = multipleDays
            ? "Tieni premuto e trascina per spostare, anche in un altro giorno; trascina il bordo in basso per la durata; tocca due volte un'ora vuota per aggiungere."
            : "Tieni premuto e trascina per spostare, trascina il bordo in basso per la durata, tocca due volte un'ora vuota per aggiungere."
        return "\(gestures) \(alignment)"
    }
}

/// Barra degli strumenti della modifica (vivace, in basso al posto della barra delle schede):
/// allineamento, nuovo intervallo, colori della giornata e "Fine".
struct TimetableEditToolbar: View {
    let addBreak: () -> Void
    let colorDay: () -> Void
    let done: () -> Void

    var body: some View {
        FloatingToolbar(vibrant: true) {
            TimetableAlignmentPicker(inToolbar: true)
            ToolbarSeparator()
            ToolbarIconButton("coffee", label: "Nuovo intervallo", action: addBreak)
            ToolbarIconButton("palette", label: "Colora la giornata", action: colorDay)
            ToolbarTextButton(title: "Fine", icon: "check", action: done)
                .padding(.leading, 4)
        }
    }
}

/// Campo con un orario (pillola piena): toccandolo si apre il selettore dell'orario di Material 3
/// (`M3TimePickerSheet`). Prima c'era un `DatePicker` di sistema quasi invisibile sopra il campo,
/// che non si apriva più (e se ne intravedeva il testo).
struct TimeField: View {
    @Binding var minutes: Int
    var minWidth: CGFloat = 96
    /// Occupa tutta la larghezza (campi dei moduli).
    var expands = false
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            Text(TimeOfDay.string(minutes))
                .font(.m3(expands ? 15 : 16).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(maxWidth: expands ? .infinity : nil, minHeight: 44, alignment: expands ? .leading : .center)
                .frame(minWidth: minWidth)
                .background(Theme.surfaceContainerHighest, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
                .contentShape(.rect(cornerRadius: Theme.radii.l))
        }
        .buttonStyle(.pressable(radius: Theme.radii.l, pressed: Theme.radii.m))
        .fixedSize(horizontal: !expands, vertical: true)
        .accessibilityLabel("Orario")
        .accessibilityValue(TimeOfDay.string(minutes))
        .accessibilityHint("Sceglie un orario")
        .sheet(isPresented: $picking) {
            M3TimePickerSheet(minutes: minutes) { minutes = $0 }
        }
        #if DEBUG
        // Script di prova (`-BCWScript`): apre il selettore dell'orario.
        .debugAction("timepicker") { picking = true }
        #endif
    }
}
