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
I widget sono un secondo target (`BCWWidgets`, incorporato nell'app) che condivide con l'app la cartella `Shared/` e l'App Group `group.com.bcw-classeviva.app`: firmando con il proprio team va scelto anche per l'estensione, con un App Group a disposizione del team.
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
- account BCW: abbini uno o più account Classeviva ed entri in tutti con un solo accesso, su ogni dispositivo e anche nella versione web; impostazioni, aspetto e orario (con i file allegati) si sincronizzano, e in Impostazioni › Account scegli cosa sincronizzare
- ricerca in compiti, voti, comunicazioni, materiale e note dalla barra in cima alla Dashboard
- in Tu una sezione "Da vedere" raccoglie comunicazioni e note da leggere e assenze da giustificare
- bacheca con adesione, firma e risposta alle comunicazioni e apertura degli allegati con Quick Look
- modalità Demo con dati di esempio, per provare l'app senza un account o anche con un account già collegato (uscendo si torna all'account)
- toccando di nuovo la scheda Dashboard si torna in cima alla pagina e, se si è già in cima, alla giornata di domani
- riepilogo per periodo con le insufficienze
- conto alla rovescia alle prossime vacanze
- notifiche per nuovi voti, comunicazioni, note, assenze e compiti, da attivare in Impostazioni › Notifiche (anche con l'app chiusa)
- in cima alla Dashboard la settimana (vista Lista) o il mese (vista Calendario) come fila di pulsanti; toccando il periodo si sceglie una data qualsiasi e scorrendo di lato si passa al giorno prima o dopo
- in "Nei prossimi giorni" ogni giorno si comprime toccandone il titolo; toccando la data o il resto si va a quel giorno

### Orario

La scheda Orario contiene l'orario settimanale, che si compila a mano o si genera dalle lezioni registrate:

- due viste: Lista (la settimana in alto e gli eventi del giorno sotto) e Giorno (le ore della giornata, come nell'app Calendario)
- in cima la settimana è una fila di pulsanti, uno per giorno; le frecce cambiano settimana, toccando le date si sceglie un giorno qualsiasi dal calendario e scorrendo di lato sugli eventi si passa al giorno prima o dopo, come nella Dashboard
- aprendo l'Orario si vede oggi finché c'è una lezione da finire, poi il primo giorno successivo con lezioni (come il widget Orario); a quel giorno riportano anche il pulsante accanto al giorno in grande ("Oggi", "Domani" o il giorno della settimana) e un nuovo tocco sulla scheda Orario
- accanto al giorno in grande, attivandola in Impostazioni › Orario, la percentuale e la barra di avanzamento della giornata: la parte passata della durata complessiva delle lezioni (ondulata mentre la giornata è in corso); la stessa impostazione vale per i widget
- la scheda Orario si può nascondere da Impostazioni › Orario (widget e attività in diretta continuano a funzionare e aprono la Dashboard)
- oggi una scheda in cima mostra la lezione in corso (quanto manca) e quella dopo, oppure la prossima lezione; il pulsante con il lucchetto la porta nella schermata di blocco come attività in diretta, o la toglie
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
- backup dell'orario da esportare e reimportare dalle Impostazioni (con file allegati)
- con un account BCW l'orario di ogni account abbinato, con i file allegati, si sincronizza tra i dispositivi

### Widget

Widget per la schermata Home e la schermata di blocco, con i colori, il font e le forme dell'app (in chiaro e in scuro, anche con le icone colorate o trasparenti di iOS):

- Orario (piccolo, medio, grande): il giorno (con la percentuale e la barra di avanzamento della giornata, se attivate), sotto le lezioni in una lista segmentata con quella in corso più alta e in evidenza e un piccolo stacco al posto degli intervalli; finita l'ultima lezione il giorno seguente con lezioni, come la scheda Orario all'apertura; nel grande la giornata intera
- Lezione in corso (piccolo e schermata di blocco): la materia, l'aula, quanto manca con la barra o l'anello di avanzamento e la lezione dopo; senza lezioni in corso la prossima
- Compiti e verifiche (medio e grande): i prossimi compiti, verifiche ed eventi giorno per giorno
- Prossima verifica (piccolo e schermata di blocco): la prossima verifica con i giorni che mancano
- Media (piccolo e schermata di blocco): la media generale nell'anello dei Voti e quella del periodo in corso

Toccando un widget si apre l'app sul giorno o sulla scheda giusta. I widget si aggiornano da soli quando cambiano i dati nell'app e all'inizio e alla fine di ogni lezione; senza account invitano ad accedere e senza orario a crearlo.

### Attività in diretta

Su iPhone la lezione in corso resta nella schermata di blocco e nella Dynamic Island come attività in diretta, con i colori del tema, il font e le forme dell'app, in chiaro e in scuro:

- nella schermata di blocco una scheda con la materia nel suo colore, aula e docente, il tempo che manca, la barra di avanzamento con gli orari e la lezione dopo
- prima della prima lezione il conto alla rovescia all'inizio, negli intervalli quanto manca alla lezione successiva e in che aula si terrà, all'ultima lezione l'avviso che è l'ultima
- nella Dynamic Island a sinistra la sigla della materia in una forma del suo colore e a destra il tempo che manca, attaccati alla fotocamera come chiedono le linee guida di Apple; con più attività un anello di avanzamento; tenendola premuta si allarga con tutti i dettagli
- le verifiche del giorno sono segnate sulla loro lezione, anche con "Mostra le verifiche" spenta
- in Impostazioni › Orario si sceglie se farla partire da sola nei giorni di lezione: compare mezz'ora prima della prima lezione e sparisce dopo l'ultima, e il giorno di scuola successivo viene preparato in anticipo, così parte anche con l'app chiusa
- dalla scheda in cima all'orario di oggi si avvia o si ferma a mano; fermata o tolta dalla schermata di blocco, quel giorno non riparte da sola
- il conto alla rovescia usa il carattere di sistema arrotondato: su iOS 27 con un carattere personalizzato l'estensione andava in crash, l'attività veniva chiusa appena avviata o mostrava una rotella
- tornando nell'app l'attività già in corso viene rifatta da capo (senza che si veda); se iOS non la accetta o la chiude appena avviata, un avviso lo dice

### iPad

Sull'iPad con la finestra larga l'app prende la struttura della versione web sugli schermi grandi, con i componenti dell'app:

- senza Liquid Glass in alto il logo, la ricerca in tutto il registro, Aggiorna, Impostazioni e l'account; a sinistra la barra di navigazione con Dashboard, Orario, Voti, Tu e tutte le sezioni di Tu (Bacheca, note, scrutini, assenze, materiale e le altre) divise in gruppi, con i conteggi da leggere; la pagina sta in un pannello con angoli ampi. In orizzontale la barra è espansa con i nomi, in verticale è ridotta e il pulsante del menu la apre sopra la pagina
- con Liquid Glass la barra delle schede in vetro in alto e la barra laterale di sistema con le stesse sezioni, l'account, Impostazioni e Aggiorna
- la Dashboard affianca la settimana (o il mese) e "Nei prossimi giorni" al giorno scelto
- l'Orario nella vista Lista affianca la settimana e il riepilogo dei giorni alle lezioni del giorno; la vista Giorno mostra la settimana intera, con il mese e il riepilogo a lato quando c'è spazio, e nella modifica gli eventi si spostano anche da un giorno all'altro
- i Voti mettono la media e l'andamento accanto agli ultimi voti, e la materia mette media, periodi e obiettivo accanto al grafico e ai voti
- Tu ha il profilo accanto alle statistiche e le sezioni in colonne; la Bacheca e le Impostazioni hanno l'elenco a sinistra e la comunicazione o il pannello scelto a destra, come la posta
- scrutini, anni precedenti, assenze e registro delle lezioni sono in due colonne; agenda, assenze, materiale e risultati della ricerca in colonne; note, materie e libri in una larghezza comoda da leggere
- l'accesso è una card a due colonne, con il logo e la spiegazione a sinistra e il modulo a destra
- fogli e moduli sono finestre centrate; i selettori della data e dell'orario sono finestre di dialogo piccole
- nelle finestre strette (Split View, Slide Over, finestre piccole) torna il layout dell'iPhone e la sezione aperta resta aperta dentro Tu; ruotando, la comunicazione o il pannello delle Impostazioni aperti restano aperti
- l'attività in diretta dell'orario compare anche nella schermata di blocco dell'iPad
- nelle finestre di iPadOS le barre in cima lasciano libero l'angolo con i controlli della finestra

### Design

L'app segue Material 3 Expressive, con colori, font e pagina Aspetto della [versione web](https://kubos5.github.io/BCW-web): font Google Sans Flex, icone Material Symbols e colori generati dal colore d'accento scelto in Impostazioni › Aspetto (con stile dei colori, contrasto, angoli e animazioni).
Anche l'esperienza d'uso è quella di un'app Material 3 Expressive: barra di ricerca in alto, liste segmentate, chip di stato, gruppi di pulsanti collegati, schede, menu del pulsante d'azione flottante e barra degli strumenti flottante, con le animazioni a molla e le transizioni di Material 3.
Le forme usano angoli continui e su iPhone l'interfaccia ha il feedback aptico.
In Impostazioni › Aspetto si può attivare Liquid Glass: barra di navigazione, barra delle schede e menu diventano quelli di sistema, in vetro.
In Impostazioni › Aspetto › Icona dell'app si sceglie il colore dell'icona: quello del tema dell'app (ogni colore d'accento proposto ha il suo, per un colore scelto a mano il più vicino) oppure Mattone, Arancio, Oro, Verde, Petrolio, Blu, Indaco, Viola, Rosa, Ardesia o Grafite. Cerchio e barra sono due lastre di vetro, come nelle icone di iOS. L'icona segue sempre le icone chiare, scure, colorate e trasparenti di iOS. Mentre iOS cambia l'icona un avviso in basso dice che il cambio è in corso. La scelta si sincronizza con l'account BCW.

### Requisiti

- Xcode 26 o successivo
- iOS / iPadOS 26 o successivo

---

## Come funziona

BCW usa le stesse API REST usate dall'app ufficiale di Classeviva (`https://web.spaggiari.eu/rest/v1`), come il progetto per Windows [ClassevivaPCTO](https://github.com/Gabboxl/ClassevivaPCTO) a cui si ispira.

Le credenziali sono salvate nel Portachiavi del dispositivo e inviate ai server di Classeviva.
Le risposte vengono salvate nella cache dell'app per l'uso offline.
L'orario è salvato sul dispositivo, separato per ogni account.
Per i widget l'app scrive nel contenitore dell'App Group un riassunto dei dati che mostrano (orario dei prossimi giorni, compiti e verifiche, medie, colori del tema), senza credenziali.
L'attività in diretta non ha bisogno di un server: l'app la aggiorna quando è aperta, a ogni passaggio di lezione, e prova a farlo in background; ogni aggiornamento contiene anche la fase successiva, che iOS mostra da sola quando la lezione finisce, anche se l'app non si è risvegliata. Senza server iOS fa questo passaggio una volta sola: se l'app resta chiusa più a lungo, il conto alla rovescia si ferma alla fine della lezione successiva e l'attività si rimette in pari appena l'app si apre o si aggiorna in background. Quando parte un'attività preparata in anticipo, iOS mostra un avviso con la prima lezione.

### Account BCW

Nella schermata di accesso un gruppo di pulsanti sceglie tra Classeviva e Account BCW. Un account BCW (nome utente e password) vive sul server [BCW-api](https://github.com/kubos5/BCW-api), un Cloudflare Worker con un database D1:

- gli account Classeviva abbinati sono salvati sul server, con le credenziali cifrate: entrando con l'account BCW l'app li riceve e accede a Classeviva come con un account del dispositivo; aggiungere o togliere un account lo abbina o lo scollega
- impostazioni (tranne blocco, promemoria, notifiche e Liquid Glass), aspetto (anche l'icona dell'app) e orario di ogni account abbinato, con i file allegati, si sincronizzano con la versione web e con gli altri dispositivi
- in Impostazioni › Account › Da sincronizzare si sceglie, per ogni dispositivo, cosa sincronizzare: impostazioni, aspetto, icona dell'app, compiti fatti e orario
- da Impostazioni › Account si accede o si crea un account BCW anche con un account Classeviva già aperto, e gli account del dispositivo si possono abbinare subito
- chi entra con un account Classeviva vede in Impostazioni › Account a quali account BCW è abbinato e può scollegarsi da ognuno: il server verifica l'accesso con il token della sessione di Classeviva, senza la password
- uscendo dall'account BCW gli account abbinati e i loro dati spariscono dal dispositivo e tornano quelli salvati sul dispositivo

L'indirizzo predefinito del server è in `BCWServer.defaultURL` (`BCW/Networking/BCWClient.swift`) e si cambia da Impostazioni › Account › Server BCW.

Per gli anni precedenti l'app scarica le pagelle dall'archivio di Classeviva (`webYY.spaggiari.eu`, es. `web25` per il 2025/26).
Voti, assenze e note degli anni passati non sono disponibili tramite le API, quindi l'app apre il sito di Classeviva in un browser integrato.

### Struttura del codice

```
BCW/
├── App/            Entry point, barra delle schede, barra laterale e pannello dell'iPad, blocco biometrico
├── Networking/     Client Classeviva e BCW-api, cache su disco, Portachiavi
├── Models/         Modelli decodificati in modo tollerante
├── Store/          Stato dell'app, sincronizzazione con l'account BCW, orario e sua generazione, calcolo medie, preferenze, promemoria, widget e attività in diretta, server demo
├── Design/         Material 3 Expressive: aspetto, font, forme, controlli, elenchi, menu e pagine
├── Theme/          Colori e stili
├── Utilities/      Date, decodifica e piccoli adattatori
├── Components/     Componenti riutilizzabili (card, badge voto, anelli, righe agenda…)
└── Features/       Dashboard, Orario, Voti, Tu (e sottosezioni), Cerca, Impostazioni, Login
Shared/             Codice comune all'app e ai widget: dati dei widget, giorno dell'orario, collegamenti, viste dei widget e dell'attività in diretta
BCWWidgets/         Estensione dei widget e dell'attività in diretta (elenco dei widget, linea temporale, icone)
```

---

## Licenza

Distribuito con licenza MIT. Vedi [LICENSE](LICENSE).
