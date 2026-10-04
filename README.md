# BCW: Better ClasseViVa
Un client nativo per iPhone, iPad e Mac per il registro elettronico [Classeviva](https://web.spaggiari.eu) di Gruppo Spaggiari Parma.

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
6. per la versione Mac scegli "My Mac" come destinazione ed esegui

Il progetto usa le cartelle sincronizzate di Xcode 16, quindi qualsiasi file aggiunto in `BCW/` entra automaticamente nel target.
In alternativa è incluso un `project.yml` per [XcodeGen](https://github.com/yonaskolb/XcodeGen).

---

## Funzioni

BCW ha parità di funzioni con il client ufficiale di classeiviva, più extra:

- puoi segnare i compiti come fatti e, opzionalmente, nasconderli
- puoi ricevere promemoria la sera prima di compiti o verifiche a un orario specificato
- dato un obiettivo di media, puoi calcolare il voto necessario nelle prossime 1-5 prove
- puoi vedere l'effetto di ogni voto sulla media della materia (▲/▼) e grafici dell'andamento
- puoi scegliere se calcolare la media come media di tutti i voti o media delle medie, con o senza pesi
- integrazione con il Calendario di iOS e macOS per compiti, verifiche ed eventi
- puoi bloccare l'app con FaceID / TouchID (anche su Mac)
- puoi consultare l'app anche offline, visualizzando i dati dell'ultima volta che era stata aperta
- supporto agli account genitore con più figli
- puoi aggiungere più account e passare dall'uno all'altro
- bacheca con adesione, firma e risposta alle comunicazioni e apertura degli allegati con Quick Look
- modalità Demo con dati di esempio, per provare l'app senza un account
- riepilogo per periodo con le insufficienze
- conto alla rovescia alle prossime vacanze

### Su Mac

BCW è anche un'app nativa per macOS (non Catalyst), con le stesse funzioni e lo stesso design dell'app per iPhone, ma con un layout pensato per lo schermo grande:

- barra laterale con tutte le sezioni (Dashboard, Voti, Tu, Cerca, Bacheca, Note, Scrutini, Assenze, Didattica…) e i contatori delle cose da leggere o giustificare
- Dashboard a colonne: calendario e prossimi giorni a sinistra, il giorno scelto a destra, con le lezioni in una colonna a parte
- Voti con medie e andamento sempre visibili accanto all'elenco
- Bacheca con elenco e comunicazione aperta affiancati, come in Mail
- griglie di card per note, assenze, agenda, materiale, materie e libri
- menu Vai e Account, scorciatoie da tastiera (⌘1…⌘9 per le sezioni, ⌘R per aggiornare, ⌘← ⌘→ ⌘T per spostarsi tra i giorni)
- finestra Impostazioni (⌘,) a schede
- le pagine si adattano alla larghezza della finestra: se è stretta, le colonne si impilano

### Design

L'app usa componenti nativi di iOS e macOS per barre, pulsanti e barra laterale.
New York è il font usato, una typeface serif creata da Apple.
Vengono usati colori morbidi (`#F7F2E8` per lo sfondo chiaro, `#1E1D1C` per lo sfondo scuro) in tutta l'interfaccia

### Requisiti

- Xcode 26 o successivo
- iOS / iPadOS 26 o successivo
- macOS 26 o successivo

---

## Come funziona

BCW usa le stesse API REST usate dall'app ufficiale di Classeviva (`https://web.spaggiari.eu/rest/v1`), come il progetto per Windows [ClassevivaPCTO](https://github.com/Gabboxl/ClassevivaPCTO) a cui si ispira.

Le credenziali sono salvate solo nel Portachiavi del dispositivo e inviate esclusivamente ai server di Classeviva.
Le risposte vengono salvate nella cache dell'app per l'uso offline.

Per gli anni precedenti l'app scarica le pagelle dall'archivio di Classeviva (`webYY.spaggiari.eu`, es. `web25` per il 2025/26).
Voti, assenze e note degli anni passati non sono disponibili tramite le API, quindi l'app apre il sito di Classeviva in un browser integrato (su Mac nel browser predefinito).

### Struttura del codice

```
BCW/
├── App/            Entry point, tab bar (iOS), finestra con barra laterale e menu (macOS), blocco biometrico
├── Networking/     Client Classeviva, cache su disco, Portachiavi
├── Models/         Modelli decodificati in modo tollerante
├── Store/          Stato dell'app, calcolo medie, preferenze, promemoria, server demo
├── Theme/          Colori, font e stili
├── Utilities/      Date, decodifica e adattatori tra iOS e macOS
├── Components/     Componenti riutilizzabili (card, badge voto, anelli, righe agenda…)
└── Features/       Dashboard, Voti, Tu (e sottosezioni), Cerca, Impostazioni, Login
```

---

## Licenza

Distribuito con licenza MIT. Vedi [LICENSE](LICENSE).
