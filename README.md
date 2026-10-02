# BCW — Better ClasseViVa

**BCW** (Better ClasseViVa, con la **W** al posto delle due **V**) è un'app iOS nativa per il registro elettronico
[Classeviva](https://web.spaggiari.eu) di Gruppo Spaggiari Parma: compiti, verifiche, voti, lezioni, bacheca,
note, assenze, materiale didattico, scrutini e anno precedente, in un'interfaccia SwiftUI curata.

> BCW è un client **non ufficiale** e non è affiliato a Gruppo Spaggiari Parma S.p.A.

## Struttura dell'app

| Scheda | Contenuto |
| --- | --- |
| **Dashboard** | Striscia settimanale o calendario mensile (a scelta) con compiti, verifiche ed eventi. Si apre di default su **domani**. Per ogni giorno mostra assenze, ritardi e uscite anticipate e, per i giorni passati, le **lezioni svolte** in una sezione separata. Sotto, i prossimi giorni con qualcosa in programma. |
| **Voti** | Media generale e medie dei singoli periodi (trimestre/pentamestre, quadrimestri…), grafico dell'andamento, lista degli ultimi voti **espandibile** con tutte le informazioni e **filtrabile per materia e periodo**. Vista per materia con grafico, docenti e calcolatore dell'obiettivo. |
| **Tu** | Profilo e riepilogo (media, assenze, ritardi, uscite) e tutte le altre funzioni di Classeviva: bacheca, scrutini, assenze e ritardi, note disciplinari e annotazioni, materiale didattico (cartelle per docente, filtrabile), anno precedente, registro delle lezioni, agenda completa, materie e docenti, libri di testo, calendario scolastico, account e impostazioni. |
| **Cerca** | Ricerca globale su agenda, voti, bacheca, materiale didattico e note. |

### Funzioni in più rispetto a Classeviva

- **Compiti spuntabili**: segna i compiti come fatti (anche dal menu contestuale) e, se vuoi, nascondili.
- **Promemoria locali** la sera prima di compiti e verifiche, all'orario che scegli (nessun server di terze parti).
- **"Quanto devo prendere?"**: dato un obiettivo di media, calcola il voto necessario nelle prossime 1–5 prove.
- **Effetto di ogni voto** sulla media della materia (▲/▼) e grafici dell'andamento.
- Calcolo della media configurabile: media di tutti i voti o media delle medie, con o senza pesi.
- **Aggiungi al Calendario** di iOS per compiti, verifiche ed eventi (senza chiedere permessi).
- **Blocco con Face ID / Touch ID**.
- **Modalità offline**: gli ultimi dati scaricati restano consultabili senza connessione.
- Supporto agli **account genitore** con più figli (scelta del profilo all'accesso).
- Bacheca con **adesione, firma e risposta** alle comunicazioni e apertura degli allegati con Quick Look.
- **Modalità demo** con dati di esempio, per provare l'app senza un account.
- Riepilogo per periodo con le insufficienze, in vista degli scrutini; conto alla rovescia alle prossime vacanze.

## Design

- Componenti nativi di iOS 26: `NavigationStack`, `TabView` e toolbar usano automaticamente il **Liquid Glass**;
  pulsanti `.glass` / `.glassProminent` e `glassEffect` per gli elementi flottanti.
- Font **New York** (il serif di sistema di Apple) ovunque, anche nei titoli della barra di navigazione.
- Sfondo **crema** in modalità chiara (`#F7F2E8`) e **grigio grafite caldo** in modalità scura (`#1E1D1C`),
  mai bianco o nero puro. Accento rosso mattone, come l'inchiostro delle correzioni.
- Card morbide, anelli per le medie, colori stabili per ogni materia, chip di filtro, feedback aptico.

## Requisiti

- Xcode 26 o successivo
- iOS / iPadOS 26 o successivo

## Compilare ed eseguire

1. Apri `BCW.xcodeproj` in Xcode.
2. In *Signing & Capabilities* scegli il tuo team (serve anche solo un Apple ID gratuito per il dispositivo).
3. Esegui sul simulatore o su un iPhone. Senza account puoi toccare **Prova la demo**.

Il progetto usa le cartelle sincronizzate di Xcode 16+: qualsiasi file aggiunto in `BCW/` entra automaticamente
nel target. In alternativa è incluso un `project.yml` per [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Come vengono ottenuti i dati

BCW usa le stesse API REST usate dall'app ufficiale di Classeviva (`https://web.spaggiari.eu/rest/v1`), come il
progetto per Windows [ClassevivaPCTO](https://github.com/Gabboxl/ClassevivaPCTO) a cui si ispira:

- `POST /auth/login` con codice utente e password restituisce un token (`Z-Auth-Token`), rinnovato
  automaticamente alla scadenza;
- gli endpoint sotto `/students/{id}/…` forniscono voti, periodi, materie, agenda, lezioni, assenze, bacheca,
  note, materiale didattico, documenti, calendario e libri di testo.

Le credenziali sono salvate solo nel **Portachiavi** del dispositivo e inviate esclusivamente ai server di
Classeviva. Le risposte vengono salvate nella cache dell'app per l'uso offline.

L'**anno precedente** viene letto dall'archivio di Classeviva (`webYY.spaggiari.eu`, es. `web25` per il 2025/26)
con le stesse credenziali; se la scuola non lo rende disponibile l'app lo segnala.

## Struttura del codice

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

## Licenza

Distribuito con licenza MIT. Vedi [LICENSE](LICENSE).
