# CLAUDE.md — BCW (Better ClasseViVa)

Contesto del progetto per Claude Code. Rispondi all'utente in **italiano**.

## Cos'è
App iOS nativa (SwiftUI, iOS 26+, Xcode 26) per il registro elettronico **Classeviva** di Spaggiari.
Nome: **BCW** = Better ClasseViVa (W al posto di VV). Ispirata a https://github.com/Gabboxl/ClassevivaPCTO (client Windows).

## Requisiti dell'utente (da rispettare)
- **Dashboard**: lista *o* vista calendario dei prossimi compiti ed eventi; si apre di default sul **giorno dopo**.
  Mostra assenze/ritardi/uscite anticipate se presenti; per i **giorni passati** mostra anche le **lezioni**
  del giorno, in una sezione separata da compiti ed eventi.
- **Voti**: media generale + medie dei singoli periodi (trimestre/pentamestre, quadrimestri…); sotto, lista
  degli ultimi voti con info rilevanti, **espandibile** e **filtrabile per materia e periodo**.
- **Tu**: overview account + tutte le altre funzioni: bacheca, scrutini, assenze e ritardi, note disciplinari e
  annotazioni, file docenti (cartelle, filtrabili per docente), anno precedente, funzioni minori.
- **UI**: componenti nativi per elementi base (pulsanti, nav bar **Liquid Glass** nativa); font **New York**
  (serif di Apple) ovunque; sfondo scuro = **grigio scuro, non nero**; sfondo chiaro = **bianco crema, non bianco**;
  il resto curato e coerente. L'utente gradisce funzioni extra utili.

## Stato attuale
- Il progetto compila e gira sul simulatore. `xcode-select` punta ai Command Line Tools, quindi per compilare da
  terminale serve `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BCW.xcodeproj -scheme BCW -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Per provare le modifiche visive usare "Prova la demo" (`DemoServer.swift`).

## Architettura
- `BCW.xcodeproj` usa **cartelle sincronizzate** (objectVersion 77): i file in `BCW/` entrano nel target da soli.
  `project.yml` è un'alternativa per XcodeGen.
- Build settings: `SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency.
- `Networking/ClassevivaClient.swift`: client REST, `Transport` sostituibile (live/demo), rinnovo token,
  `DiskCache` per l'offline, `fetchFirst` per endpoint versionati.
- `Models/`: decodifica **tollerante** via `KeyedDecodingContainer<AnyKey>` (`c.string/int/double/bool/array`),
  perché l'API non è documentata e i tipi cambiano.
- `Store/AppModel.swift`: stato globale `@Observable`, con **più account** salvati (`SavedAccount` nel Portachiavi,
  `activeAccount` in UserDefaults, cache separata per account `live-<id>`); gli errori delle sezioni secondarie
  (scrutini, didattica, libri) non finiscono nel banner globale `lastError`; `Preferences` (UserDefaults); `GradeBook` (medie,
  andamento, voto necessario); `Reminders` (notifiche locali); `ArchiveModel` (anno precedente);
  `DemoServer.swift` (dati finti deterministici per "Prova la demo").
- `Theme/Theme.swift`: palette (crema `#F7F2E8` / grafite `#1E1D1C`, accento `#A23E2F`), font New York anche
  nella UINavigationBar, modificatore `.card()`.
- `Features/`: Dashboard, Grades, You (sottosezioni), Search, Settings, Login.

## API Classeviva
- Base `https://web.spaggiari.eu/rest/v1`, header `User-Agent: CVVS/std/4.2.3 Android/12`,
  `Z-Dev-Apikey: Tg1NWEwNGIgIC0K`, token in `Z-Auth-Token`.
- **Le POST senza dati vanno inviate con corpo vuoto** (Content-Length 0): il server risponde
  `400 101:CvvRestApi/invalid payload` al JSON `{}` (verificato), e il CDN rifiuta POST senza Content-Length.
  `URLSessionTransport` normalizza `{}` → corpo vuoto. `noticeboard/attach` richiede di aver prima letto la
  comunicazione (`item must first be read`).
- `POST /auth/login` `{uid, pass, ident}` → token, oppure `choices` per account genitore multi-figlio.
- Endpoint sotto `/students/{id}/` (id = cifre dell'ident, `S1234567X` → `1234567`): `card`, `grades`,
  `periods`, `subjects`, `agenda/all/{yyyyMMdd}/{yyyyMMdd}`, `lessons/{da}/{a}`, `absences/details`,
  `noticeboard` (+ `read/{evtCode}/{pubId}/101`, `attach/{evtCode}/{pubId}/{n}`), `notes/all`
  (+ `notes/{code}/read/{id}`), `didactics` (+ `didactics/item/{contentId}`), `documents` (POST, + `check/{hash}`,
  `read/{hash}`), `calendar/all`, `schoolbooks`.

## Punti NON verificati con un account reale
- Anni precedenti (verificato): tutti i `webYY.spaggiari.eu` puntano a `storico.spaggiari.eu`. `web22`–`web24`
  non hanno l'API REST (il login risponde 204 vuoto); `web25` sì, ma accetta solo date dell'anno in corso
  ("dates must be between 20260901 and …"), quindi voti/assenze/note risultano vuoti. Funzionano solo i documenti
  (pagelle). Scelta dell'utente: l'app mostra le pagelle e apre il sito di Classeviva in `SFSafariViewController`
  per il resto ("Vai all'a.s. …" dal menu). Il sito d'archivio rimanda sempre al login principale senza ritorno.
  Gli archivi vivono in `AppModel.archive(for:)` e si azzerano a ogni cambio di sessione.
- Endpoint voti: si prova `grades`, poi `grades2324`, poi `grades2`.
- Verifiche riconosciute con euristica sul testo (`AgendaEvent.kind`), Classeviva non ha un codice dedicato.

## Convenzioni
- Testi UI e commenti in italiano. Stile: card, `Eyebrow`, `FilterChip`, `StatTile`, `GradeBadge`, `AverageRing`,
  `Pill` (stati su una riga, con versione abbreviata).
- Sezioni comprimibili: sempre `CollapsibleContent` (scorre ritagliato con sfumatura in alto) e intestazione con
  `HeaderButtonStyle` (niente attenuazione alla pressione), dentro `withAnimation(.snappy)`.
- Pagine lunghe (Tu, Account, Impostazioni): margine in fondo `Theme.bottomInset`. iOS rimpicciolisce la tab bar
  scorrendo solo se la pagina è abbastanza lunga (verificato: Tu con 24 punti non lo faceva, con 120 sì).
- README: niente trattini lunghi, niente grassetto/corsivo nelle parti aggiunte, tabelle solo se indispensabili.
- Non usare nero/bianco puri come sfondo; usare sempre i colori di `Theme`.
