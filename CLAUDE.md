# CLAUDE.md — BCW (Better ClasseViVa)

Contesto del progetto per Claude Code. Rispondi all'utente in **italiano**.

## Cos'è
App nativa per iOS e macOS (SwiftUI, iOS/macOS 26+, Xcode 26) per il registro elettronico **Classeviva** di Spaggiari.
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
  Per il Mac: `-destination 'platform=macOS'` (in locale aggiungere `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`).
- Per provare le modifiche visive usare "Prova la demo" (`DemoServer.swift`). Si avvia anche con l'argomento
  `-demoMode YES`.
- Screenshot del Mac senza permessi di registrazione schermo (solo DEBUG, `App/DebugSnapshots.swift`):
  avviare con `-demoMode YES -BCWSnapshot YES -BCWSections dashboard,grades -BCWSizes 1280x840,900x640`
  (facoltativi `-BCWSettings YES`, `-appearance light`, `-BCWDaysAgo 2`, `-BCWOpenNotice YES`, `-dashboardMode calendar`,
  `-BCWHover YES` per portare il puntatore sulla barra della finestra, `-BCWSearch testo` per aprire e chiudere la ricerca,
  `-BCWOpenSubject YES` per aprire in Voti la materia con il nome più lungo, cioè una pagina aperta da un'altra);
  le immagini finiscono in `~/Library/Containers/com.bcw-classeviva.app/Data/tmp/BCWSnapshots` (o in `-BCWSnapshotDir`
  con un build senza sandbox) e l'app si chiude da sola.
- Simulatori: sono disponibili iOS 26.3 e iOS 27. Lo strumento del simulatore di Claude Code (tocchi, pressioni lunghe,
  screenshot) funziona con il simulatore acceso; per le animazioni registrare con `simctl io … recordVideo`. Quello di iOS 27 appena avviato satura la CPU per minuti e fa
  bloccare `simctl install/launch`: tenerne acceso uno alla volta.

## Architettura
- `BCW.xcodeproj` usa **cartelle sincronizzate** (objectVersion 77): i file in `BCW/` entrano nel target da soli.
- **Un solo target multipiattaforma** (iOS + macOS nativo, non Catalyst; `SUPPORTED_PLATFORMS`, `SDKROOT = auto`).
  Su macOS: sandbox con rete in uscita e Calendario (impostazioni `ENABLE_*[sdk=macosx*]`).
- Differenze tra piattaforme: `Utilities/Platform.swift` (`Platform.copy`, `screenTitle`, `.trailingBar`,
  `pagePadding`, `CardGrid` (anche `equalRowHeights`), `ChipRow`, `glassButton`, `PlatformNavigationStack`,
  `SplitColumns`/`StackAware`, `sheetFrame`, `macToolbarBackground`, `localSearchable`/`LocalSearchField`,
  `InlineProgress`, `CenteredCircle`, `pushedPageActions`, `UnobservedValue`). Usare questi invece di `#if` sparsi o di
  API UIKit/AppKit nelle viste.
- iOS, ricerca: `.searchable` sta dentro la scheda Cerca (`SearchView`), con `Tab(role: .search)`. Con l'SDK di
  iOS 27 la scheda finirebbe dentro la barra e il campo in alto: da iOS 27 in poi `MainTabView` applica
  `.tabViewSearchActivation(.searchTabSelection)` (verificato: torna il pulsante separato con il campo in basso;
  selezionando la scheda si apre subito la tastiera e la X riporta alla scheda precedente). `.searchable` sulla
  `TabView` invece mette il campo anche in Dashboard: non usarlo.
- iOS, barra delle schede: tenendo premuta la scheda Tu si apre il popup degli account (`TabBarItemLongPress`, un
  riconoscitore di pressione prolungata sulla `UITabBar` che risponde solo sopra quella scheda e, quando scatta,
  annulla i gesti della barra, altrimenti la scheda verrebbe selezionata). `Tab.contextMenu` su iPhone non fa nulla
  (verificato). Toccando di nuovo Dashboard (`MainTabView.tabSelection` riconosce il secondo tocco) si torna in
  cima, o a domani se si è già in cima (`DashboardView.reselection`).
  In tutte le schede il ritorno in cima è quello del sistema, che funziona solo con il titolo grande nella riga dei
  pulsanti (`inlineLargeTitleDisplay()`, cioè `.toolbarTitleDisplayMode(.inlineLarge)`, come nella Dashboard). Con il
  titolo grande su una riga a parte (lo stile predefinito) il sistema si ferma sotto la barra con il titolo ancora
  compresso, e scorrere ancora da codice dopo o insieme al sistema dà uno scatto (verificato, anche con `ScrollPosition`):
  le pagine principali delle schede vanno tenute in `.inlineLarge`.
- Account: su iOS il popup `AccountSwitcherSheet` (dal basso, in vetro, rilevamenti medio/grande) mostra la stessa
  `AccountsSection` della pagina Account; si apre dal pulsante in alto a destra in Tu e tenendo premuta la scheda Tu, e
  si chiude da solo quando comincia il cambio. Su macOS c'è `AccountMenuItems` nella barra laterale. La demo non è un
  account: non entra nel conteggio (icona del pulsante, testi), si apre con "Prova la demo" anche con un account
  collegato (`activeAccountID` resta impostato e uscendo si torna a quello).
- Cambio di sessione (altro account, demo, uscita dalla demo verso un account, rimozione dell'account attivo, account
  aggiunto ad app aperta): `AppModel.changeSession` sfuma l'interfaccia (`isChangingSession`, opacità in `RootView`),
  cambia i dati senza animazioni mentre non si vede e la fa riapparire quando ci sono i dati (subito con la cache,
  altrimenti a fine aggiornamento, al massimo 3 s). Così niente si ridimensiona davanti all'utente. Su macOS la barra
  della finestra resta: i suoi elementi stanno in `NSToolbar`, fuori dal contenuto (ricerca e barra laterale sono di
  sistema e non sfumerebbero comunque).
- macOS: `App/MacRootView.swift` (NavigationSplitView con `MacSection`, account in fondo alla barra laterale,
  `BCWCommands` per i menu Vai/Account e le scorciatoie, `MacNavigation` ricorda l'ultima sezione e tiene lo stato
  della ricerca generale: campo `.searchable` sulla split view, sempre visibile a destra; selezionarlo o scrivere
  apre `SearchView` nel dettaglio, `nav.show(_:)` torna a una sezione chiudendo la ricerca, ⌘F la attiva), finestra
  `Window` singola + scena `Settings` (`MacSettingsView` a schede, con le stesse sezioni di `SettingsView`).
  I titoli sono etichette in New York nella barra (`screenTitle`): applicarlo dopo `.toolbar` della pagina,
  così resta il primo elemento. `.primaryAction` su macOS sta a sinistra: per il lato destro usare `.trailingBar`.
  Distanziatore e Aggiorna (`macWindowActions`) stanno sulla pagina principale di ogni sezione; ogni pagina aperta da
  un'altra (`NavigationLink`, `navigationDestination`) deve avere `.pushedPageActions()`, altrimenti sostituisce la
  barra: Aggiorna sparisce e la ricerca va accanto al titolo. Agganciati alla finestra o alla pila (verificato)
  restano, ma accanto al titolo. Con poco spazio il campo di ricerca diventa un'icona
  che si espande premendola (come in Note): `SearchFieldCompaction` regola la soglia sotto cui `NSSearchToolbarItem`
  diventa icona (proprietà non pubblica `minimumWidthForSearchFieldRepresentation`, di serie 160; con controllo
  `responds(to:)`). Con le due colonne (dettaglio ≥ 780 punti) 260 punti; con una colonna la larghezza piena meno 1 e una
  riserva invisibile di 65 punti (un quinto del campo) in `macWindowActions`, prima del distanziatore: il campo resta
  esteso solo se è pieno e oltre a lui resta vuoto almeno un quinto della sua larghezza. La riserva ha priorità di
  visibilità bassa (se manca posto esce lei, non un pulsante); se esce dalla barra viene ridotta a 1 punto
  (`searchReserveIsTight`), altrimenti lo spazio avanzato finisce tra Aggiorna e l'icona; torna intera quando c'è posto.
  Il suo `id` contiene la larghezza, così la barra la reinserisce. Durante la ricerca non c'è. Chiudendo la ricerca (Esc, clic altrove, scelta di una
  sezione) la pagina torna solo 250 ms dopo che il campo ha perso il focus (`closeSearch`, `searchEndRequest`): se la
  barra della pagina arriva mentre il campo è ancora aperto, AppKit la impagina con il campo largo e non la ricalcola più
  (Aggiorna nell'overflow, lente in mezzo). Abbassare `preferredWidthForSearchField` non va: la lente non si apre più al
  clic e il campo della ricerca resta minuscolo. Si prova con `-BCWSearch` e `-BCWClickSearch` (clic simulato sulla lente).
  Verificato che NON funzionano:
  `.searchToolbarBehavior(.minimize)` (non esiste su macOS), alzare `preferredWidthForSearchField` o priorità bassa del campo
  (si stringe), `prefersCompactRepresentation` o una soglia enorme o pari alla larghezza massima (la lente resta in
  mezzo allo spazio del campo), la riserva agganciata alla finestra (finisce prima del campo o prima del titolo).
  Prima di pubblicare su App Store valutare se tenere la proprietà non pubblica.
  `project.yml` è un'alternativa per XcodeGen.
- Icona: `Resources/AppIcon.icon` (Icon Composer, con varianti chiara/scura/tinta), la stessa per iOS e macOS;
  il nome corrisponde a `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Nel catalogo `Assets.xcassets` non c'è più
  un `AppIcon.appiconset`: non aggiungerlo, andrebbe in conflitto.
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
- `Networking/Keychain.swift`: su macOS usa il Portachiavi moderno (data protection) e ripiega su quello di login
  se l'app non è firmata con un team (`errSecMissingEntitlement`).
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

## Layout su macOS
- Barra laterale al posto delle schede; "Tu" diventa un riepilogo (profilo, statistiche, riquadri delle sezioni).
- Pagine a due colonne con `SplitColumns` (laterale fissa + principale, scorrimento separato; sotto ~780 pt si
  impilano): Dashboard (calendario + prossimi giorni | giorno, con lezioni in colonna a parte da 580 pt), Voti,
  dettaglio materia, Scrutini, Anni precedenti, Lezioni. Bacheca: elenco + dettaglio affiancati sopra 820 pt.
- Elenchi di card in `CardGrid` (una colonna su iOS, griglia adattiva su Mac); filtri in `ChipRow` (a capo su Mac).
- Dashboard su Mac: titolo grande nel contenuto (sopra il calendario); nella barra frecce/Oggi/Domani e il menu della
  vista (senza "Vai a oggi"), che un distanziatore invisibile allinea al bordo destro della card del calendario
  (`menuSpacer`, calcolato da Oggi/Domani e dal calendario in coordinate `.global`; zero sotto i 780 punti, perché
  all'apertura `SplitColumns` mostra per un istante le due colonne e quella misura può arrivare in ritardo). NSToolbar non ridimensiona
  bene un elemento che cambia larghezza (lo centra nel vecchio spazio e decide l'overflow su misure vecchie): il
  distanziatore ha un `id` che cambia con la larghezza, così viene reinserito, e con le colonne impilate non c'è.
  Non misurare elementi della barra che dipendono dal distanziatore: si creano cicli e i tasti finiscono nell'overflow.
  "Nei prossimi giorni" cambia identità (`upcomingGeneration`) in `select(_:)`, insieme al giorno: su iOS sempre, su
  macOS solo se la sezione è espansa e il contenuto cambia davvero. L'identità non deve dipendere dallo stato
  compresso: comprimere sostituirebbe la sezione intera e l'intestazione scenderebbe e risalirebbe. La transizione
  usa lo spostamento del giorno scelto (`upcomingTransition`, `dayDetailHeight`): `.move(edge:)` sposta di tutta
  l'altezza della vista, troppo con la lista aperta e troppo poco con la sola intestazione.
- Barra della finestra: `macToolbarBackground()` (in `screenTitle` e nella Dashboard) fa cominciare il contenuto 1 pt
  sotto la barra, rende trasparente lo sfondo della barra e ci mette sotto `Theme.background`. Senza, macOS 27 schiarisce
  e sottolinea la barra al passaggio del cursore sopra ogni area scorrevole che la tocca (con `SplitColumns` solo sopra
  una colonna). Non usare `toolbarBackground(_:for: .windowToolbar)`: colora anche la barra laterale.
  La schermata di accesso ha un elemento invisibile nella barra: senza barra i pulsanti a semaforo si spostano.
- Pagine con ricerca propria (Bacheca, Agenda, Materiale): su Mac il campo è nel contenuto (`LocalSearchField`),
  perché nella barra c'è già quello generale.
- `ContentUnavailableView` su macOS non si allarga: dentro uno stack aggiungere `.frame(maxWidth: .infinity)`.
  Le pagine che mostrano un messaggio in `.overlay` devono riempire la finestra (`frame(maxWidth:maxHeight: .infinity)`).
- Rotelle in pulsanti e righe: `InlineProgress` (piccola su Mac, dove quella normale è più alta della riga).
- `.glass` su macOS riempie il pulsante con la tinta: usare `glassButton()`. Anni precedenti apre il sito nel
  browser (niente `SFSafariViewController`); "Aggiungi al Calendario" salva direttamente con accesso in sola scrittura.

## Prestazioni
- Eventi, assenze e giorni del calendario per giorno: usare `model.events(on:)`, `absences(on:)`, `calendarStatus(on:)`,
  che leggono indici ricostruiti quando cambiano i dati. Confrontare le date con `isSameDay` su tutto l'elenco è lento
  (il calendario di Foundation dominava i profili) e le celle del calendario lo fanno a ogni aggiornamento.
- Nelle viste calcolare gli elenchi una volta per aggiornamento (`let` nel `body`, o una struttura come
  `DayDetail.Content` e `SearchView.Results`), mai in proprietà calcolate richiamate più volte o dentro le righe.
- Misure che cambiano a ogni fotogramma e servono solo in certi momenti (es. `dayDetailHeight`) vanno in
  `UnobservedValue`, non in uno `@State` osservato: altrimenti l'intera pagina si ricalcola a ogni fotogramma.
- `.card()` mette l'ombra sulla sola forma di sfondo: un'ombra sull'intera vista va ricalcolata dal contenuto.
- Per misurare: build Release del Mac con `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG`, un aggancio temporaneo che ripete
  l'interazione e `sample <pid> 8`, poi sommare i campioni per funzione dell'app.

## Convenzioni
- Testi UI e commenti in italiano. Stile: card, `Eyebrow`, `FilterChip`, `StatTile`, `GradeBadge`, `AverageRing`,
  `Pill` (stati su una riga, con versione abbreviata).
- Sezioni comprimibili: sempre `CollapsibleContent` (scorre ritagliato con sfumatura in alto) e intestazione con
  `HeaderButtonStyle` (niente attenuazione alla pressione), dentro `withAnimation(.snappy)`.
  Da chiusa (animazione finita) il contenuto non viene né costruito né disegnato (`CollapseBody`, vista animabile che
  chiama la closure solo quando serve): non costa nulla e, se cambiasse mentre è nascosto, le sue animazioni non si
  vedrebbero sotto l'intestazione, dove la maschera si allarga per le ombre. Lo stato interno del contenuto (es. una
  riga espansa) si azzera chiudendo la sezione.
- Pagine lunghe (Tu, Account, Impostazioni): margine in fondo `Theme.bottomInset`. iOS rimpicciolisce la tab bar
  scorrendo solo se la pagina è abbastanza lunga (verificato: Tu con 24 punti non lo faceva, con 120 sì).
- README: niente trattini lunghi, niente grassetto/corsivo nelle parti aggiunte, tabelle solo se indispensabili.
- Non usare nero/bianco puri come sfondo; usare sempre i colori di `Theme`.
