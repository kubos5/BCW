# BCW: Better ClasseViVa
Un client nativo per iPhone e iPad per il registro elettronico [Classeviva](https://web.spaggiari.eu) di Gruppo Spaggiari Parma.

> BCW non è affiliato a Gruppo Spaggiari Parma S.p.A.

---

## Installazione

Finché l'app non sarà disponibile su App Store, consiglio usare [AltStore](https://altstore.io/) per firmare l'IPA.

Altrimenti, puoi compilarla in Xcode:

### Installazione manuale con Xcode

1. installa Xcode dall'App Store
2. clona `https://github.com/kubos5/BCW` da Xcode
   - oppure `git clone https://github.com/kubos5/BCW`, poi apri il progetto con Xcode
4. in Signing & Capabilities scegli il tuo team / creane uno (è sufficiente un qualsiasi Apple ID)
5. esegui sul simulatore o su un dispositivo collegato via USB

Il progetto usa le cartelle sincronizzate di Xcode 16, quindi qualsiasi file aggiunto in `BCW/` entra automaticamente nel target.
In alternativa è incluso un `project.yml` per [XcodeGen](https://github.com/yonaskolb/XcodeGen).

---

## Funzioni

BCW ha parità di funzioni con il client ufficiale di classeiviva, più extra:

- puoi segnare i compiti come fatti e, opzionalmente, nasconderli
- puoi ricevere promemoria la sera prima di compiti o verifiche a un orario specificato
- dato un obiettivo di media, puoi calcolare il voto necessario nelle prossime 1-5 prove
- puoi vedere l'effetto di ogni voto sulla media della materia (▲/▼) e grafici dell'andamento (toccando il grafico si legge la media di quel giorno)
- puoi scegliere se calcolare la media come media di tutti i voti o media delle medie, con o senza pesi
- integrazione con il Calendario di iOS per compiti, verifiche ed eventi
- puoi bloccare l'app con FaceID / TouchID
- puoi consultare l'app anche offline, visualizzando i dati dell'ultima volta che era stata aperta
- supporto agli account genitore con più figli
- puoi aggiungere più account e passare dall'uno all'altro (dall'avatar in Dashboard o tenendo premuta la scheda Tu), con una dissolvenza tra i dati di un account e quelli dell'altro
- ricerca in compiti, voti, comunicazioni, materiale e note dalla barra in cima alla Dashboard
- in Tu una sezione "Da vedere" raccoglie comunicazioni e note da leggere e assenze da giustificare
- bacheca con adesione, firma e risposta alle comunicazioni e apertura degli allegati con Quick Look
- modalità Demo con dati di esempio, per provare l'app senza un account o anche con un account già collegato (uscendo si torna all'account)
- toccando di nuovo la scheda Dashboard si torna in cima alla pagina e, se si è già in cima, alla giornata di domani
- riepilogo per periodo con le insufficienze
- conto alla rovescia alle prossime vacanze
- notifiche per nuovi voti, comunicazioni, note, assenze e compiti, da attivare in Impostazioni › Notifiche (anche con l'app chiusa)
- in cima alla Dashboard la settimana (o il mese, che scorrendo si chiude nella settimana) come fila di pulsanti; toccando il periodo si sceglie una data qualsiasi e scorrendo di lato si passa al giorno prima o dopo
- in "Nei prossimi giorni" ogni giorno si comprime toccandone il titolo; toccando la data o il resto si va a quel giorno

### Orario

La scheda Orario contiene l'orario settimanale, che si compila a mano o si genera dalle lezioni registrate:

- due viste: Lista (la settimana in alto e gli eventi del giorno sotto) e Giorno (le ore della giornata, come nell'app Calendario)
- in cima la settimana è una fila di pulsanti, uno per giorno; le frecce cambiano settimana, toccando le date si sceglie un giorno qualsiasi dal calendario e scorrendo di lato sugli eventi si passa al giorno prima o dopo, come nella Dashboard
- oggi una scheda in cima mostra la lezione in corso (quanto manca) e quella dopo, oppure la prossima lezione
- toccando un evento si vedono i dettagli e si aggiungono note, file e foto, per un solo giorno o per ogni settimana
- le verifiche segnate dai docenti su Classeviva compaiono da sole sulla lezione della materia e si possono nascondere; altre verifiche si segnano a mano, per un giorno o per ogni settimana
- Verifiche nascoste (dal menu dell'orario): l'elenco delle verifiche nascoste, con il motivo, da cui si possono mostrare di nuovo, e le regole per nasconderle in automatico (per docente, materia, giorno della settimana, periodo, parole nel testo o materie che quel giorno non sono in orario)
- modificando un evento si può applicare la modifica a tutti quelli con lo stesso nome
- gli eventi uguali di seguito (es. due ore di matematica) sono uniti in un gruppo, quelli contemporanei sono affiancati
- intervalli che nella vista Giorno stanno sopra le lezioni senza cambiarne la durata e nella vista Lista sono un separatore ondulato con l'orario
- le verifiche nella vista Lista si mostrano solo attivando "Mostra le verifiche" (Impostazioni o menu dell'orario)
- il pulsante + apre un menu con nuovo evento, nuovo intervallo, Modifica orario e generazione dalle lezioni
- modalità Modifica orario, nella vista Giorno, con una barra degli strumenti in basso (allineamento, intervalli, colori): gli eventi si spostano tenendoli premuti e trascinandoli, si allungano dal bordo inferiore, se ne crea uno nuovo toccando due volte un'ora vuota e toccandoli si modificano gli orari a mano
- allineamento dell'orario, scelto in Modifica orario: automatico (eventi da 30 minuti o un'ora, alla mezz'ora, anche inserendo gli orari a mano) o libero (qualsiasi orario e durata); passando all'automatico gli eventi non allineati vengono allineati dopo una conferma; gli intervalli si posizionano sempre liberamente
- colori: quelli delle lezioni, colori personalizzati salvati, colori presi dalle palette (anche personalizzate) oppure una palette a sfumatura applicata a una serie di eventi di una giornata
- generazione automatica di una bozza dell'orario dalle lezioni registrate, mostrata in anteprima con i bordi tratteggiati prima di applicarla
- backup dell'orario da esportare e reimportare dalle Impostazioni (con file allegati); la sincronizzazione con iCloud è in lavorazione

### Design

L'app segue Material 3 Expressive, con colori, font e pagina Aspetto della [versione web](https://kubos5.github.io/BCW-web): font Google Sans Flex, icone Material Symbols e colori generati dal colore d'accento scelto in Impostazioni › Aspetto (con stile dei colori, contrasto, angoli e animazioni).
Anche l'esperienza d'uso è quella di un'app Material 3 Expressive: barra di ricerca in alto, liste segmentate, chip di stato, gruppi di pulsanti collegati, schede, menu del pulsante d'azione flottante e barra degli strumenti flottante, con le animazioni a molla e le transizioni di Material 3.
Le forme usano angoli continui e su iPhone l'interfaccia ha il feedback aptico.
In Impostazioni › Aspetto si può attivare Liquid Glass: barra di navigazione, barra delle schede e menu diventano quelli di sistema, in vetro.

### Requisiti

- Xcode 26 o successivo
- iOS / iPadOS 26 o successivo

---

## Come funziona

BCW usa le stesse API REST usate dall'app ufficiale di Classeviva (`https://web.spaggiari.eu/rest/v1`), come il progetto per Windows [ClassevivaPCTO](https://github.com/Gabboxl/ClassevivaPCTO) a cui si ispira.

Le credenziali sono salvate solo nel Portachiavi del dispositivo e inviate esclusivamente ai server di Classeviva.
Le risposte vengono salvate nella cache dell'app per l'uso offline.
L'orario è salvato solo sul dispositivo, separato per ogni account.

Per gli anni precedenti l'app scarica le pagelle dall'archivio di Classeviva (`webYY.spaggiari.eu`, es. `web25` per il 2025/26).
Voti, assenze e note degli anni passati non sono disponibili tramite le API, quindi l'app apre il sito di Classeviva in un browser integrato.

### Struttura del codice

```
BCW/
├── App/            Entry point, barra delle schede, blocco biometrico
├── Networking/     Client Classeviva, cache su disco, Portachiavi
├── Models/         Modelli decodificati in modo tollerante
├── Store/          Stato dell'app, orario e sua generazione, calcolo medie, preferenze, promemoria, server demo
├── Design/         Material 3 Expressive: aspetto, font, forme, controlli, elenchi, menu e pagine
├── Theme/          Colori e stili
├── Utilities/      Date, decodifica e piccoli adattatori
├── Components/     Componenti riutilizzabili (card, badge voto, anelli, righe agenda…)
└── Features/       Dashboard, Orario, Voti, Tu (e sottosezioni), Cerca, Impostazioni, Login
```

---

## Licenza

Distribuito con licenza MIT. Vedi [LICENSE](LICENSE).
