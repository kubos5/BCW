# BCW: Better ClasseViVa
Un client iOS nativo per il registro elettronico [Classeviva](https://web.spaggiari.eu) di Gruppo Spaggiari Parma.

> BCW non è affiliato a Gruppo Spaggiari Parma S.p.A.

## Funzioni

BCW ha **parità di funzioni** con il client ufficiale di classeiviva, più extra:

- puoi segnare i compiti come fatti e, opzionalmente, nasconderli
- puoi ricevere promemoria la sera prima di compiti o verifiche a un orario specificato
- dato un obiettivo di media, puoi calcolare il voto necessario nelle prossime 1-5 prove
- puoi vedere l'effetto di ogni voto sulla media della materia (▲/▼) e grafici dell'andamento
- puoi scegliere se calcolare la media come media di tutti i voti o media delle medie, con o senza pesi
- integrazione con il calendario di iOS per compiti, verifiche ed eventi
- puoi bloccare l'app con FaceID / TouchID
- puoi consultare l'app anche offline, visualizzando i dati dell'ultima volta che era stata aperta
- supporto agli account genitore con più figli
- puoi aggiungere più account e passare dall'uno all'altro
- bacheca con adesione, firma e risposta alle comunicazioni e apertura degli allegati con Quick Look
- modalità Demo con dati di esempio, per provare l'app senza un account
- riepilogo per periodo con le insufficienze
- conto alla rovescia alle prossime vacanze

### Design

L'app usa componenti nativi di iOS per la nav bar e pulsanti.
New York è il font usato, una typeface serif creata da Apple.
Vengono usati colori morbidi (`#F7F2E8` per lo sfondo chiaro, `#1E1D1C` per lo sfondo scuro) in tutta l'interfaccia

### Requisiti

- Xcode 26 o successivo
- iOS / iPadOS 26 o successivo

---

## Installazione

Finché l'app non sarà disponibile su App Store, consiglio usare [AltStore](https://altstore.io/) per firmare l'IPA.

Altrimenti, puoi compilarla in Xcode:

### Installazione manuale con Xcode

1. Installa Xcode dall'App Store
2. Clona questa repo
3. In Signing & Capabilities scegli il tuo team / creane uno (è sufficiente un qualsiasi Apple ID)
4. Esegui sul simulatore o su un dispositivo collegato via USB

1. Apri `BCW.xcodeproj` in Xcode.
2. In *Signing & Capabilities* scegli il tuo team (serve anche solo un Apple ID gratuito per il dispositivo).
3. Esegui sul simulatore o su un iPhone. Senza account puoi toccare **Prova la demo**.

Il progetto usa le cartelle sincronizzate di Xcode 16, quindi qualsiasi file aggiunto in `BCW/` entra automaticamente nel target.
In alternativa è incluso un `project.yml` per [XcodeGen](https://github.com/yonaskolb/XcodeGen).

---

## Come funziona

BCW usa le stesse API REST usate dall'app ufficiale di Classeviva (`https://web.spaggiari.eu/rest/v1`), come il progetto per Windows [ClassevivaPCTO](https://github.com/Gabboxl/ClassevivaPCTO) a cui si ispira.

Le credenziali sono salvate solo nel Portachiavi del dispositivo e inviate esclusivamente ai server di Classeviva.
Le risposte vengono salvate nella cache dell'app per l'uso offline.

Per gli anni precedenti l'app scarica le pagelle dall'archivio di Classeviva (`webYY.spaggiari.eu`, es. `web25` per il 2025/26).
Voti, assenze e note degli anni passati non sono disponibili tramite le API, quindi l'app apre il sito di Classeviva in un browser integrato.

### Struttura del codice

```
BCW/
├── App/            Entry point, tab bar, blocco biometrico
├── Networking/     Client Classeviva, cache su disco, Portachiavi
├── Models/         Modelli decodificati in modo tollerante
├── Store/          Stato dell'app, calcolo medie, preferenze, promemoria, server demo
├── Theme/          Colori, font e stili
├── Components/     Componenti riutilizzabili (card, badge voto, anelli, righe agenda…)
└── Features/       Dashboard, Voti, Tu (e sottosezioni), Cerca, Impostazioni, Login
```

---

## Licenza

Distribuito con licenza MIT. Vedi [LICENSE](LICENSE).
