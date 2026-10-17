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
        let gestures = "Tieni premuto e trascina per spostare, trascina il bordo in basso per la durata, tocca due volte un'ora vuota per aggiungere."
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

/// Campo con un orario (pillola piena): toccandolo si apre il selettore di sistema.
struct TimeField: View {
    @Binding var minutes: Int
    var minWidth: CGFloat = 96
    /// Occupa tutta la larghezza (campi dei moduli).
    var expands = false

    var body: some View {
        ZStack(alignment: expands ? .leading : .center) {
            Text(TimeOfDay.string(minutes))
                .font(.m3(expands ? 15 : 16).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(maxWidth: expands ? .infinity : nil, minHeight: 44, alignment: expands ? .leading : .center)
                .frame(minWidth: minWidth)
                .background(Theme.surfaceContainerHighest, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
            // Il selettore di sistema sta sopra, quasi invisibile: lo apre un tocco sul campo.
            DatePicker("Orario", selection: Binding { TimeOfDay.date(minutes) } set: { minutes = TimeOfDay.minutes(of: $0) },
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(maxWidth: expands ? .infinity : nil, minHeight: 44)
                .frame(minWidth: minWidth)
                .scaleEffect(x: 1.6, y: 1)
                .opacity(0.011)
                .clipped()
        }
        .fixedSize(horizontal: !expands, vertical: true)
    }
}
