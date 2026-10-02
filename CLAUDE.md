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
- Codice scritto in una sessione cloud **senza Xcode**: **mai compilato né eseguito**. Primo passo consigliato:
  `xcodebuild -project BCW.xcodeproj -scheme BCW -destination 'platform=iOS Simulator,name=iPhone 17' build`
  (adatta il nome del simulatore) e correggi gli errori.
- Branch di lavoro: `claude/relaxed-faraday-35jvyx`.

## Architettura
- `BCW.xcodeproj` usa **cartelle sincronizzate** (objectVersion 77): i file in `BCW/` entrano nel target da soli.
  `project.yml` è un'alternativa per XcodeGen.
- Build settings: `SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency.
- `Networking/ClassevivaClient.swift`: client REST, `Transport` sostituibile (live/demo), rinnovo token,
  `DiskCache` per l'offline, `fetchFirst` per endpoint versionati.
- `Models/`: decodifica **tollerante** via `KeyedDecodingContainer<AnyKey>` (`c.string/int/double/bool/array`),
  perché l'API non è documentata e i tipi cambiano.
- `Store/AppModel.swift`: stato globale `@Observable`; `Preferences` (UserDefaults); `GradeBook` (medie,
  andamento, voto necessario); `Reminders` (notifiche locali); `ArchiveModel` (anno precedente);
  `DemoServer.swift` (dati finti deterministici per "Prova la demo").
- `Theme/Theme.swift`: palette (crema `#F7F2E8` / grafite `#1E1D1C`, accento `#A23E2F`), font New York anche
  nella UINavigationBar, modificatore `.card()`.
- `Features/`: Dashboard, Grades, You (sottosezioni), Search, Settings, Login.

## API Classeviva
- Base `https://web.spaggiari.eu/rest/v1`, header `User-Agent: CVVS/std/4.2.3 Android/12`,
  `Z-Dev-Apikey: Tg1NWEwNGIgIC0K`, token in `Z-Auth-Token`.
- `POST /auth/login` `{uid, pass, ident}` → token, oppure `choices` per account genitore multi-figlio.
- Endpoint sotto `/students/{id}/` (id = cifre dell'ident, `S1234567X` → `1234567`): `card`, `grades`,
  `periods`, `subjects`, `agenda/all/{yyyyMMdd}/{yyyyMMdd}`, `lessons/{da}/{a}`, `absences/details`,
  `noticeboard` (+ `read/{evtCode}/{pubId}/101`, `attach/{evtCode}/{pubId}/{n}`), `notes/all`
  (+ `notes/{code}/read/{id}`), `didactics` (+ `didactics/item/{contentId}`), `documents` (POST, + `check/{hash}`,
  `read/{hash}`), `calendar/all`, `schoolbooks`.

## Punti NON verificati con un account reale
- Anno precedente: ipotesi host d'archivio `https://webYY.spaggiari.eu/rest/v1` (es. `web25` per 2025/26).
- Endpoint voti: si prova `grades`, poi `grades2324`, poi `grades2`.
- Verifiche riconosciute con euristica sul testo (`AgendaEvent.kind`), Classeviva non ha un codice dedicato.

## Convenzioni
- Testi UI e commenti in italiano. Stile: card, `Eyebrow`, `FilterChip`, `StatTile`, `GradeBadge`, `AverageRing`.
- Non usare nero/bianco puri come sfondo; usare sempre i colori di `Theme`.
