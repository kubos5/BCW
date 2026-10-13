import SwiftUI

/// Allineamento di tutto l'orario. Passando all'automatico con eventi fuori dalle ore e dalle
/// mezz'ore chiede prima conferma, perché quegli eventi verranno spostati (e divisi, se più
/// lunghi di un'ora).
struct TimetableAlignmentPicker: View {
    @Environment(AppModel.self) private var model
    var segmented = false
    @State private var confirming = false

    private var store: TimetableStore { model.timetable }

    var body: some View {
        let picker = Picker("Allineamento", selection: Binding(get: { store.alignment }, set: request)) {
            ForEach(TimetableAlignment.allCases) { alignment in
                Text(alignment.shortTitle).tag(alignment)
            }
        }
        Group {
            if segmented {
                picker
                    .pickerStyle(.segmented)
                    .labelsHidden()
            } else {
                picker
            }
        }
        .alert("Allineare gli eventi?", isPresented: $confirming) {
            Button("Allinea") {
                withAnimation(.snappy) { store.setAlignment(.automatic) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    private func request(_ alignment: TimetableAlignment) {
        guard alignment != store.alignment else { return }
        if alignment == .automatic && !store.unalignedEntries.isEmpty {
            confirming = true
        } else {
            withAnimation(.snappy) { store.setAlignment(alignment) }
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

/// Barra della modalità di modifica: allineamento e istruzioni.
struct TimetableEditBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("Allineamento", systemImage: model.timetable.alignment.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
                Spacer(minLength: 0)
                TimetableAlignmentPicker(segmented: true)
                    .frame(maxWidth: 260)
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)
                // Niente `fixedSize` verticale: fuori da uno scorrimento macOS chiederebbe l'altezza
                // del testo largo zero e la finestra impaginerebbe tutto fuori posto.
                .lineLimit(4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.accentSoft.opacity(0.45))
        }
    }

    private var hint: String {
        let alignment = model.timetable.alignment == .automatic
            ? "Scatti di mezz'ora, eventi da 30 minuti o un'ora."
            : "Scatti di 5 minuti; orari esatti dall'evento."
        let gestures = Platform.isMac
            ? "Trascina per spostare (anche in un altro giorno), trascina il bordo in basso per la durata, doppio clic su un'ora vuota per aggiungere."
            : "Tieni premuto e trascina per spostare, trascina il bordo in basso per la durata, tocca due volte un'ora vuota per aggiungere."
        return "\(gestures) \(alignment) Intervalli sempre liberi."
    }
}
