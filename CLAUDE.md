# CLAUDE.md — BCW (Better ClasseViVa)

Contesto del progetto per Claude Code. Rispondi all'utente in **italiano**.

## Cos'è
App nativa per iPhone e iPad (SwiftUI, iOS 26+, Xcode 26) per il registro elettronico **Classeviva** di Spaggiari.
Nome: **BCW** = Better ClasseViVa (W al posto di VV). Ispirata a https://github.com/Gabboxl/ClassevivaPCTO (client Windows).

## Requisiti dell'utente (da rispettare)
- **Dashboard**: lista *o* vista calendario dei prossimi compiti ed eventi; si apre di default sul **giorno dopo**.
  Mostra assenze/ritardi/uscite anticipate se presenti; per i **giorni passati** mostra anche le **lezioni**
  del giorno, in una sezione separata da compiti ed eventi.
- **Voti**: media generale + medie dei singoli periodi (trimestre/pentamestre, quadrimestri…); sotto, lista
  degli ultimi voti con info rilevanti, **espandibile** e **filtrabile per materia e periodo**.
- **Orario** (scheda tra Dashboard e Voti): orario settimanale dell'utente in tre viste (Lista, Calendario,
  Giorno), con note/file/verifiche per giorno o ricorrenza, verifiche automatiche da Classeviva (nascondibili),
  modifiche estese agli eventi con lo stesso nome, gruppi di eventi uguali accostati, eventi contemporanei
  affiancati, intervalli in primo piano, colori e
  palette (anche su una serie di eventi di una giornata), bozza generata dalle lezioni con anteprima tratteggiata,
  backup esportabile/importabile (due conferme) e sincronizzazione con l'account BCW.
  "Modifica orario" (menu del pulsante d'azione flottante) apre la modifica grafica, sempre nella vista Giorno: spostare e
  ridimensionare gli eventi, doppio tocco per crearli, tocco per l'editor. Lì si sceglie l'allineamento, che vale
  per tutto l'orario (non solo per il trascinamento): automatico = eventi da 30/60 minuti alla mezz'ora (anche gli
  orari inseriti a mano), libero = qualsiasi orario. Passando a automatico con eventi non allineati serve una
  conferma, poi vengono allineati (quelli più lunghi di un'ora divisi in eventi uguali di seguito).
- **Tu**: overview account + tutte le altre funzioni: bacheca, scrutini, assenze e ritardi, note disciplinari e
  annotazioni, file docenti (cartelle, filtrabili per docente), anno precedente, funzioni minori.
- **UI**: stile **Material 3 Expressive** come la versione web (https://kubos5.github.io/BCW-web, stesso layout,
  stessi colori e font Google Sans Flex, stessa pagina Aspetto), ma sempre SwiftUI nativo; forme con **supercerchi**
  (angoli continui); feedback aptico su iOS. In Impostazioni › Aspetto c'è "Liquid Glass: sì/no": con "no" tutto è
  come sul web; con "sì" barra di navigazione, barra delle schede e pulsanti dei menu sono quelli di sistema in vetro.
  L'utente gradisce funzioni extra utili.
- **UX** (scelta dell'utente, ottobre 2026): non più quella dell'app originale ma quella di una vera app M3 Expressive,
  con le stesse funzioni e le stesse quattro schede (Dashboard, Orario, Voti, Tu). Senza Liquid Glass la ricerca è
  una barra in cima alla Dashboard (con vista e avatar dell'account) che si allarga nella pagina di ricerca; con
  Liquid Glass resta la scheda Cerca di sistema. Giorno in grande con chip di stato (Dashboard e Orario), sezioni
  segmentate, "Nei prossimi giorni" come la vista Programma di Google Calendar, menu del FAB nell'Orario, barra degli
  strumenti flottante vivace in modifica (al posto della barra delle schede), media in primo piano con i periodi in un
  gruppo di pulsanti collegati e schede Material nei Voti, profilo centrato e statistiche collegate in Tu (le
  Impostazioni si aprono solo dall'ingranaggio in alto). Calendari come il selettore della data di Material 3,
  settimana dell'Orario come gruppo di pulsanti. Elenchi delle pagine secondarie in liste segmentate (niente card con
  separatori).

## Stato attuale
- Il progetto compila e gira sul simulatore. Se dopo una build riuscita l'app non cambia, controllare la data di
  `BCW.app/BCW.debug.dylib` in DerivedData: a volte xcodebuild compila ma non ricollega più (nessun passo `Ld`);
  `clean build` lo risolve. `xcode-select` punta ai Command Line Tools, quindi per compilare da
  terminale serve `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BCW.xcodeproj -scheme BCW -destination 'platform=iOS Simulator,name=iPhone 17' build`
- macOS non è più supportato in modo nativo (scelta dell'utente, ottobre 2026): niente codice, impostazioni o
  `#if os(macOS)` per il Mac.
- Per provare le modifiche visive usare "Prova la demo" (`DemoServer.swift`). Si avvia anche con l'argomento
  `-demoMode YES`.
- Argomenti di avvio per le prove (solo DEBUG, con `simctl launch … <argomenti>`): `-BCWTab timetable|grades|you|search`
  apre una scheda, `-BCWLiquidGlass YES|NO` (resta salvato), `-BCWAccent #RRGGBB` (non salvato), `-BCWTimetableDemo YES` crea l'orario della demo
  dalle lezioni se è vuoto, `-BCWHideTests YES` aggiunge una regola e una verifica nascosta,
  `-BCWTimetableSheet generator|hidden|date|editor|detail` apre il generatore (con `-BCWGeneratorBreaks N` intervalli), le verifiche
  nascoste, il selettore della data, l'editor di un evento nuovo o il dettaglio del primo evento del giorno, `-BCWTimetableDraft YES` mostra la bozza in anteprima, `-timetableMode list|day` sceglie la vista,
  `-BCWTimetableEditing YES` apre la modifica, `-BCWTimetableDay N` apre l'orario N giorni dopo oggi (i valori negativi
  non passano come argomenti), `-BCWOpenSubject YES`, `-BCWDaysAgo N`, `-BCWKeychainService nome` (Portachiavi vuoto),
  `-BCWNowMinute N` (l'orario fa come se fosse il minuto N del giorno, per l'evento "In corso", `TimeOfDay.nowMinutes`),
  `-BCWOpenPage nome` apre una pagina di Tu (bacheca, note, scrutini, anni, assenze, materiale, lezioni, agenda,
  materie, libri, calendario, account, icona, impostazioni o `impostazioni-<pane>`, es. `impostazioni-appearance`;
  `cambia-account` apre il popup degli account; serve anche `-BCWTab you`), `-BCWSearchQuery testo` apre la ricerca con quel
  testo (con `-BCWTab search`). Per l'iPad `-BCWWindowClass`, `-BCWFakeWindow`,
  `-BCWOrientation`, `-railCollapsed` e `-BCWScript` (vedi "iPad"). Le opzioni dell'icona si provano anche
  come argomenti (`-appIconShape cookie9 -appIconColor verde -appIconAppearance auto|light|dark
  -appIconDarkBackground material|ios`), letti da `ThemeStore` senza salvarli.
- Autotest dell'orario (solo DEBUG): `-BCWTimetableSelfTest YES` prova backup (esportazione, importazione, file,
  rifiuto di file non validi, riapertura da disco), modifiche estese agli eventi con lo stesso nome, generazione e
  passaggio dall'allineamento libero all'automatico;
  stampa `BCW-SELFTEST PASS/FAIL` ed esce. Sul simulatore: `simctl launch --console-pty booted com.bcw-classeviva.app
  -demoMode YES -BCWTimetableSelfTest YES`.
- Autotest dei widget (solo DEBUG): `-BCWWidgetSelfTest YES` prova la regola del giorno predefinito dell'orario, le voci
  della linea temporale, lezione in corso e prossima, i collegamenti `bcw://`, la codifica dell'istantanea, l'App Group
  e le fasi dell'attività in diretta (ore unite, pause, contenuto scaduto, stato sotto i 4 KB); stampa
  `BCW-WIDGET-SELFTEST PASS/FAIL` ed esce.
- Simulatori: sono disponibili iOS 26.3 e iOS 27. Lo strumento del simulatore di Claude Code (tocchi, pressioni lunghe,
  screenshot) funziona con il simulatore acceso; per le animazioni registrare con `simctl io … recordVideo`. Quello di iOS 27 appena avviato satura la CPU per minuti e fa
  bloccare `simctl install/launch`: tenerne acceso uno alla volta.

## Account BCW (backend BCW-api, https://github.com/kubos5/BCW-api)
- Richiesta dell'utente (ottobre 2026): account BCW (nome utente e password) a cui abbinare uno o più account
  Classeviva; entrando con l'account BCW si accede a tutti. Con l'account BCW si aggiungono e tolgono account
  Classeviva; entrando con un account Classeviva ci si scollega da qualsiasi account BCW. Nella schermata di accesso
  un gruppo di pulsanti sceglie tra Classeviva e Account BCW. Si sincronizzano impostazioni, aspetto, orario e file.
  Scelte dell'utente: Cloudflare Workers + D1, credenziali di Classeviva cifrate sul server, nome utente (niente email).
- Stessa logica della versione web (`js/cloud.js`): `Networking/BCWClient.swift` (`BCWServer` con `defaultURL`, cambiabile
  in Impostazioni › Account › Server BCW; `BCWAPI` con tutte le richieste; `BCWError` con il codice del server),
  `Store/CloudSync.swift` (coda delle operazioni, `JSONValue`, sincronizzazione), metodi `cloud…` di `AppModel`.
- `model.cloud` (`BCWSession`, nel Portachiavi `bcw.session`): con l'account BCW `accounts` sono gli account abbinati
  (id del server, nel Portachiavi `bcw.accounts`, attivo in `activeCloudAccount`); quelli del dispositivo restano in
  `classeviva.accounts` e tornano uscendo (`leaveCloud`). Senza account abbinati `LoginView` chiede di abbinare il primo
  (`linkingFirst`). `signIn` con l'account BCW abbina sul server; il cestino diventa "Scollega" (`unlinkAccount`).
  `refreshCloud` (avvio, Aggiorna, ritorno nell'app; al massimo ogni 30 s) allinea gli account; un 401 fa uscire con
  `cloudNotice`. Dopo l'accesso `localAccountsToLink` propone (dialogo in `RootView`) di abbinare gli account del
  dispositivo (`linkLocalAccounts`, copia l'orario con `TimetableStore.copyData`).
- Sincronizzazione: impostazioni sincronizzate in `Preferences.syncedValues`/`applySynced` e
  `ThemeStore.syncedValues`/`applySynced` (stessi nomi del web; blocco, promemoria, notifiche e Liquid Glass restano
  locali), avvisi con `onSyncedChange` (spenti durante `applySynced`); unione a tre vie. Orario: `TimetableStore.onSaved`
  avvisa, `applyRemote` sostituisce senza avvisare; vince il lato cambiato (entrambi = questo dispositivo, la prima
  volta il server); i file si caricano prima dell'orario e si scaricano dopo (`downloadFile`, anche aprendo un allegato).
  In secondo piano le modifiche in attesa partono subito (`flushCloudChanges` in `RootView`).
- Lato Classeviva: `ClassevivaLinksSection` (Impostazioni › Account) con `model.classevivaLinks()` e
  `removeClassevivaLink(_:)`, che inviano a BCW-api ident e token di Classeviva (`ClassevivaClient.currentSession()`);
  senza account BCW l'elenco si carica solo toccando "Mostra gli account BCW abbinati".
- Il codice non è stato compilato da Claude (niente Xcode nel suo ambiente): va provato su Xcode.

## Architettura
- `BCW.xcodeproj` usa **cartelle sincronizzate** (objectVersion 77): i file in `BCW/` entrano nel target da soli.
- Target iOS dell'app (iPhone e iPad; `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`) più l'estensione dei widget
  `BCWWidgets` (vedi "Widget e attività in diretta").
- `Utilities/Platform.swift`: piccoli adattatori (`Platform.copy`, `screenTitle`, `pagePadding`, `CardGrid`, `ChipRow`,
  `PlatformNavigationStack`, `localSearchable`, `UnobservedValue`, `LeadingColumnLayout`).
- iOS, ricerca senza Liquid Glass: la barra delle schede Material ha quattro destinazioni e la ricerca è
  `SearchAppBar` in cima alla Dashboard (`DashboardChrome`): toccandola la pillola resta sospesa e diventa il campo
  (freccia indietro, X), e `SearchView(embedded: true)` prende il posto della pagina con `.fadeThrough`; la barra delle
  schede si nasconde (`TabChrome.hidesBar`, anche per la tastiera). Niente `navigationTransition(.zoom)`: lasciava
  bande nere ai lati della pagina. Passando a Material con la scheda Cerca aperta si torna alla Dashboard.
- iOS, ricerca con Liquid Glass: `.searchable` sta dentro la scheda Cerca (`SearchView`), con `Tab(role: .search)`. Con l'SDK di
  iOS 27 la scheda finirebbe dentro la barra e il campo in alto: da iOS 27 in poi `MainTabView` applica
  `.tabViewSearchActivation(.searchTabSelection)` (verificato: torna il pulsante separato con il campo in basso;
  selezionando la scheda si apre subito la tastiera e la X riporta alla scheda precedente). `.searchable` sulla
  `TabView` invece mette il campo anche in Dashboard: non usarlo.
- iOS, barra delle schede: tenendo premuta la scheda Tu (indice 3, dopo Dashboard, Orario, Voti) si apre il popup degli account (`TabBarItemLongPress`, un
  riconoscitore di pressione prolungata sulla `UITabBar` che risponde solo sopra quella scheda e, quando scatta,
  annulla i gesti della barra, altrimenti la scheda verrebbe selezionata). `Tab.contextMenu` su iPhone non fa nulla
  (verificato). Toccando di nuovo Dashboard (`MainTabView.tabSelection` riconosce il secondo tocco) si torna in
  cima, o a domani se si è già in cima (`DashboardView.reselection`).
  In tutte le schede il ritorno in cima è quello del sistema, che funziona solo con il titolo grande nella riga dei
  pulsanti (`.toolbarTitleDisplayMode(.inlineLarge)`, messo da `pageChrome`, come nella Dashboard). Con il
  titolo grande su una riga a parte (lo stile predefinito) il sistema si ferma sotto la barra con il titolo ancora
  compresso, e scorrere ancora da codice dopo o insieme al sistema dà uno scatto (verificato, anche con `ScrollPosition`):
  le pagine principali delle schede vanno tenute in `.inlineLarge`.
- Account: su iOS il popup `AccountSwitcherSheet` (dal basso, in vetro, rilevamenti medio/grande) mostra la stessa
  `AccountsSection` della pagina Account; si apre dall'avatar nella barra di ricerca della Dashboard, dal pulsante
  "Cambia"/"Aggiungi" del profilo in Tu e tenendo premuta la scheda Tu, e
  si chiude da solo quando comincia il cambio. La demo non è un
  account: non entra nel conteggio (icona del pulsante, testi), si apre con "Prova la demo" anche con un account
  collegato (`activeAccountID` resta impostato e uscendo si torna a quello).
- Cambio di sessione (altro account, demo, uscita dalla demo verso un account, rimozione dell'account attivo, account
  aggiunto ad app aperta): `AppModel.changeSession` sfuma l'interfaccia (`isChangingSession`, opacità in `RootView`),
  cambia i dati senza animazioni mentre non si vede e la fa riapparire quando ci sono i dati (subito con la cache,
  altrimenti a fine aggiornamento, al massimo 3 s). Così niente si ridimensiona davanti all'utente.
- `project.yml` è un'alternativa per XcodeGen.
- Icona: `Resources/AppIcon.icon` (Icon Composer, a livelli di vetro: sfondo, forma e barra, con varianti
  chiara/scura/colorata) è l'icona principale, il cui nome corrisponde a `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`;
  le icone alternative stanno in `Resources/AppIcons.xcassets` (vedi "Icona dell'app"). Nel catalogo `Assets.xcassets`
  non c'è più un `AppIcon.appiconset`: non aggiungerlo, andrebbe in conflitto.
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
- `Networking/Keychain.swift`: account salvati nel Portachiavi (voci generiche, `AfterFirstUnlockThisDeviceOnly`).
- Orario: `Models/Timetable.swift` (modello `Codable` con decodifica tollerante, minuti dalla mezzanotte, giorni 1 = lunedì),
  `Store/TimetableStore.swift` (in `AppModel.timetable`, un JSON per account in Application Support/Timetable/<account>,
  file allegati in `Files`, cancellati quando nessuno li usa; la demo si cancella uscendo), `Store/TimetableGenerator.swift`,
  `Features/Timetable/`. L'allineamento automatico è una regola sui dati (`setAlignment` allinea gli eventi,
  `TimetableAlignmentPicker` chiede conferma); anche la bozza generata viene allineata. Fuori dalla modalità di
  modifica la vista Giorno è in sola lettura.
  Nelle viste Lista/Calendario gli intervalli sono separatori di sfondo (`BreakRow`, linea ondulata `WavyLine`, come
  "Libero · x min" ma con l'orario); le verifiche lì si vedono solo con `Preferences.timetableShowsTests` (spenta di
  serie, in Impostazioni e nel menu dell'orario); nel dettaglio e nella vista Giorno si vedono sempre.
  Gruppi di eventi uguali: `TimetableLayout(entries:splitAtBreaks:)`. Nelle viste Lista e Calendario
  (`splitAtBreaks: true`, righe da `listItems`) un intervallo sul passaggio tra due eventi uguali li separa e va tra
  i due; nella vista Giorno il gruppo resta unito e l'intervallo sta sopra.
  Dentro `TimetableStore.mutate` non leggere `timetable` (accesso simultaneo → crash): calcolare prima ciò che serve.
  Nella vista Giorno `contentShape` e gesti vanno prima di `.offset` (dopo valgono per la posizione di partenza);
  su iPhone il trascinamento usa `LongPressDragRecognizer` (UIKit): quelli di SwiftUI perdevano contro lo scorrimento.
  `fileImporter` chiude il selettore (e il suo `isPresented`) prima di consegnare i file: lo stato che serve dopo va
  tenuto a parte.
- `Theme/Theme.swift`: ruoli di colore Material letti da `ThemeStore` (alias `background`/`card`/`ink`…), toni fissi
  dei voti, colori delle materie (`subjectColor`), modificatore `.card()`.
- `Features/`: Dashboard, Timetable, Grades, You (sottosezioni), Search, Settings, Login.

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

## Layout e comportamenti
- Orario: solo viste Lista e Giorno (`TimetableMode.available`; il mese c'è nella Dashboard). Nella Lista: giorno in
  grande con chip e "Oggi" accanto (come la Dashboard), `TimetableNowCard` per oggi (lezione in corso con avanzamento e la
  successiva, oppure la prossima), lezioni di seguito in una lista segmentata (`Row.run`), intervalli in una pillola.
  Vista Giorno: blocchi pieni nella tinta, ore di un gruppo separate da 2 punti con angoli piccoli; lo scorrimento
  iniziale va fatto dopo la prima impaginazione (`task` con una breve attesa). Lista e Giorno si scambiano con
  `.fadeThrough`.
- Settimana e mese di Dashboard e Orario (`Components/CalendarBar.swift`): gruppo di pulsanti di M3 Expressive, fermo
  sopra l'area che scorre (in un `VStack`, non sovrapposto). Settimana: il giorno scelto pieno, tutto arrotondato e
  più largo (`WeightedRow`); mese (vista Calendario della Dashboard): gli stessi pulsanti più bassi in griglia. Vista
  Calendario = sempre il mese, vista Lista = sempre la settimana (scelta dell'utente, ottobre 2026: niente passaggio
  tra i due scorrendo né pulsante per chiudere il mese).
  Frecce e scorrimento di lato sulla barra cambiano settimana (o mese); il titolo apre `M3DatePickerSheet`.
  Alla pressione i giorni si rimpiccioliscono con il velo e stringono gli angoli, tranne quello scelto, che resta
  una pillola (come sul web, dove `.cb-day.selected` vince su `:active`).
  La settimana sta alla stessa altezza nelle due schede (verificato al pixel): con Material la barra di ricerca della
  Dashboard è 4 punti più alta del titolo grande dell'Orario, che per questo ha 4 punti in più sopra la barra.
- Vista Giorno dell'Orario con Liquid Glass: la barra di sistema segue il primo scorrimento che trova e la vista parte
  già scorsa alla prima ora, quindi il titolo diventava piccolo; uno `ScrollView` vuoto e fermo prima della vista lo
  tiene grande.
- Lezioni (Dashboard e Registro delle lezioni): `refreshAll` svuota le lezioni già scaricate, quindi chi le mostra
  le richiede di nuovo anche quando cambia `lastUpdated` (prima il Registro restava su "Caricamento…").
- Cambio di giorno (`Components/DayPager.swift`): `DaySwipe` + `DayPage` + `DaySwipeGesture`. Transizione ad asse
  condiviso X di Material 3 (`.sharedAxisX`). `DaySwipe.go(verso)` fissa prima il verso e cambia il giorno al giro
  dopo: SwiftUI prende la transizione della pagina che esce dal suo ultimo aggiornamento. Lo spostamento del dito sta
  sulla pagina (dentro l'`id`), non sul contenitore: così al rilascio la pagina vecchia esce da dove l'ha lasciata il
  dito e quella nuova entra dal lato opposto (sul contenitore entrava dalla parte sbagliata). Il gesto è un pan di UIKit
  aggiunto allo `UIScrollView` (trovato da una vista `Anchor` sullo sfondo del contenuto, a ogni spostamento nella
  gerarchia), che lo scorrimento aspetta (`shouldBeRequiredToFailBy`) e che non parte sopra elementi che scorrono di
  lato. Lo scorrimento è sempre o orizzontale o verticale: il gesto non parte se uno scorrimento sotto il dito è già in
  corso e, partito, spegne `isScrollEnabled` degli scorrimenti verticali sotto il dito fino al rilascio (dopo un cambio
  di Liquid Glass nell'Orario si scorreva anche in diagonale: il gesto poteva stare su uno scorrimento diverso). Tutte le selezioni di un giorno (barra, selettore, "Domani"/"Oggi") passano da `select`, che usa `go`.
  Le registrazioni del simulatore salvano fotogrammi solo quando lo schermo cambia (le pause spariscono): per misurare
  un'animazione stampare i valori con l'ora (`CACurrentMediaTime`).
- Impostazioni: elenco di sottopagine (Generale, Aspetto, Voti, Dashboard, Orario, Notifiche, Account).
- Dashboard, "Nei prossimi giorni": ogni giorno (`UpcomingDayCard`) ha a sinistra la data (`DateBadge`, tocco = vai al
  giorno) e a destra il nome, che comprime, e gli elementi in una lista segmentata.
  Si va al giorno solo dalla data: gli elementi hanno soltanto i loro tocchi (casella del compito, testo
  tagliato che si apre, menu contestuale).
- Notifiche delle novità (`Store/NewsNotifications.swift`): dopo ogni `refreshAll` confronta voti, comunicazioni,
  note, assenze e compiti/verifiche futuri con gli id già visti per account (`UserDefaults`), e notifica solo i tipi
  attivi in Impostazioni › Notifiche (`Preferences.newsNotifications`); la prima volta ricorda senza notificare; più
  di 4 novità di un tipo = una notifica riassuntiva. Su iPhone c'è l'aggiornamento in background
  (`.backgroundTask(.appRefresh)`, `Config/Info-iOS.plist` con `BGTaskSchedulerPermittedIdentifiers` e
  `UIBackgroundModes`, unito all'Info.plist generato). `NotificationPresenter` le mostra anche con l'app aperta (senza
  delegato iOS le scarta). `-BCWNewsDemo YES` le prova nella demo. Sul simulatore gli interruttori dei `Form` vogliono
  un tocco un po' lungo (`touch_path` di 120 ms): quello istantaneo non li cambia.
- Verifiche nascoste (menu dell'orario, `TimetableHiddenTestsView`): nascoste a mano (`hiddenTests`) o da regole
  (`Timetable.testRules`, `TestHidingRules`: docenti, materie, giorni, periodi, parole, senza lezione in orario);
  mostrandone a mano una nascosta da una regola finisce in `shownTests` (eccezione), nascondendola di nuovo l'eccezione
  si toglie. Il motivo viene da `TimetableStore.hiddenReason(for:unmatched:)`; la Dashboard non ne è toccata.
- Elenchi in liste segmentate (`ListGroup`); filtri in `ChipRow` (scorrono in orizzontale). Chip su più righe:
  `FlowLayout`, che calcola le righe allo stesso modo nelle due fasi (larghezza proposta, mezzo punto di tolleranza):
  prima, con una fila piena al punto, l'ultimo chip sotto il giorno saltava tra la riga e una riga a capo.
- Rotelle in pulsanti e righe: `InlineProgress`.

## Widget e attività in diretta
- Richiesta dell'utente (ottobre 2026): widget per iOS, tra cui l'orario di oggi che, passato l'ultimo evento, mostra
  quello del giorno successivo come l'Orario; altri widget utili. Stile Material dell'app adattato a iOS.
- Target `BCWWidgets` (`com.bcw-classeviva.app.widgets`, estensione WidgetKit incorporata in `BCW.app/PlugIns` con
  "Embed Foundation Extensions"), cartella sincronizzata `BCWWidgets/` (bundle dei widget, linea temporale, catalogo
  `Assets.xcassets/Material` con una copia delle sole icone usate). `Shared/` è una cartella sincronizzata aggiunta a
  entrambi i target: `BCWShared.swift` (App Group, calendario, `TimetableDefaultDay`, `DeepLink`), `WidgetSnapshot.swift`,
  `TimeOfDay.swift`, `ThemeDefaults.swift` (schema predefinito e toni dei voti), forme (`MaterialShape*`, `RingShape`,
  `WavyLine`) e `Shared/Widgets/` (viste, `BCWWidgetKind` con nomi, dimensioni e voci della linea temporale, stile).
  Info.plist dell'estensione: `Config/Info-Widgets.plist` (solo `NSExtension`) unito a quello generato.
- Isolamento: anche l'estensione ha `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; i tipi di dati e il fornitore della
  linea temporale sono `nonisolated` (`WidgetSnapshot`, `BCWShared`, `TimetableDefaultDay`, `DeepLink`, `BCWWidgetKind`,
  `BCWTimelineProvider`), le viste restano sull'attore principale.
- App Group `group.com.bcw-classeviva.app` (`Config/BCW.entitlements`, `Config/BCWWidgets.entitlements`). Sul simulatore i
  diritti stanno nella sezione `__entitlements` del binario ("Simulated"): `codesign -d --entitlements` li mostra vuoti,
  ma funziona (verificato: l'estensione legge l'istantanea scritta dall'app).
- Dati: `WidgetExporter` (`AppModel.widgets`, avviato da `bootstrap`) costruisce `WidgetSnapshot` (JSON in
  `<App Group>/Widgets/snapshot.json`, niente credenziali): eventi dell'orario risolti per 8 giorni (come la vista Lista:
  verifiche solo con "Mostra le verifiche"), orario settimanale per i giorni oltre, agenda di 14 giorni, medie come nei
  Voti, ruoli del tema chiaro e scuro, angoli, nome, demo. Segue con `withObservationTracking` tutto ciò che legge e
  ricostruisce dopo 700 ms (unisce le modifiche ravvicinate), non durante `refreshAll` o un cambio di sessione; scrive e
  chiama `reloadAllTimelines` solo se il contenuto cambia. Anche a mezzanotte (`significantTimeChange`), tornando
  nell'app, andando in secondo piano (`flush`) e dopo l'aggiornamento in background.
- Giorno predefinito dell'orario (`TimetableDefaultDay`, una sola implementazione per app e widget, stessa regola del
  web): oggi se c'è un evento dell'orario non ancora finito, altrimenti il primo giorno con eventi entro 7 giorni,
  altrimenti oggi; contano gli eventi dell'utente, non intervalli né verifiche di Classeviva. L'Orario lo applica solo
  all'apertura (`adjustInitialDay`): se l'ultimo evento finisce mentre lo si guarda resta su oggi. La Dashboard non ha
  un meccanismo per il ritorno nell'app dopo un po', quindi nemmeno l'Orario. "Oggi" porta sempre a oggi.
- Widget: Orario (piccolo, medio, grande), Lezione in corso (piccolo e accessori rettangolare, circolare, in linea),
  Compiti e verifiche (medio, grande), Prossima verifica (piccolo, rettangolare, in linea), Media (piccolo, circolare, in
  linea). Linea temporale: adesso, ogni inizio e fine degli eventi da oggi a dopodomani e le due mezzanotti
  (`.atEnd`); tempo che manca e avanzamento con `Text(timerInterval:)` e `ProgressView(timerInterval:)`.
- Colori: `WidgetPalette` legge i ruoli dell'istantanea secondo `colorScheme`; con le icone colorate o trasparenti
  (`accented`) e nella schermata di blocco (`vibrant`) tutto è bianco con opacità diverse e le parti in evidenza
  (tinte, icone, anelli) sono `widgetAccentable`, senza grandi riempimenti. Verificati sulla Home (anche "Tinted") e
  sulla schermata di blocco del simulatore.
- Font: `WidgetFonts` registra Google Sans Flex dal bundle dell'app che contiene l'estensione (niente copia del file);
  verificato sui widget veri.
- Collegamenti: `bcw://orario?giorno=AAAA-MM-GG`, `bcw://dashboard?giorno=…`, `bcw://voti` (`CFBundleURLTypes` in
  `Config/Info-iOS.plist`). `RootView.onOpenURL` → `AppModel.open` (accettato anche durante l'avvio) → `openedLink`:
  `MainTabView` sceglie la scheda, `TimetableView`/`DashboardView` il giorno. Verificati a freddo e a caldo, con e senza
  Liquid Glass.
- Limiti verificati: sull'iPhone 17 i widget misurano 164 (piccolo), 350 × 164 (medio), 350 × 365 (grande) con margini
  di 16 punti, meno del previsto: le viste scelgono con `ViewThatFits` quante righe e quali dettagli mostrare. Una
  parola sola non va a capo (veniva troncata accanto a un'icona): i titoli prendono tutta la larghezza. Negli accessori
  in linea entrano solo un testo e un'immagine e il sistema taglia la fine: l'ora va prima della materia. Nell'elenco
  dei widget del simulatore le app compaiono solo dopo aver toccato il campo di ricerca.
- Attività in diretta "Orario di oggi" (richiesta dell'utente, ottobre 2026: la card "Adesso" dell'Orario con la
  materia attuale e la barra, stile Material adattato alla Dynamic Island e alla schermata di blocco). Tipi in
  `Shared/LiveActivity/TimetableActivity.swift` (`TimetableActivityAttributes` con `dayKey` e `scheduledStart`,
  `TimetableActivityState`, `TimetableActivityPlan`), viste in `Shared/LiveActivity/TimetableActivityViews.swift`,
  configurazione in `BCWWidgets/TimetableLiveActivity.swift`, gestione nell'app in `Store/LiveActivityManager.swift`
  (`AppModel.liveActivities`). `NSSupportsLiveActivities` e l'identificatore `com.bcw.app.liveactivity` in
  `Config/Info-iOS.plist`.
- Fasi (`TimetableActivityPlan`, dall'istantanea dei widget, ore uguali di seguito unite): prima dell'inizio (da
  mezz'ora prima, conto alla rovescia), lezione, pausa tra due lezioni (conto alla rovescia, aula della successiva),
  lezioni finite (contenuto finale per 10 minuti, poi l'attività si chiude). Le verifiche si segnano sempre
  (`WidgetSnapshot.Event.hasTest`), anche con "Mostra le verifiche" spenta.
- Aggiornamenti senza server: `WidgetExporter` passa ogni istantanea al gestore (avvio, ritorno nell'app, `refreshAll`,
  orario cambiato, mezzanotte), che allinea le attività a quelle volute (`reconcile`: aggiorna, chiude, richiede) e,
  con l'app in esecuzione, si risveglia a ogni passaggio di fase. In secondo piano un `BGAppRefreshTask` programmato al
  passaggio successivo (sul simulatore `submit` dà sempre l'errore 1, non disponibile: non verificabile).
- Lo stato porta fino a 4 fasi con `staleDate` alla fine della prima: scaduto, la vista mostra la fase in corso al
  momento del disegno (`TimetableActivityState.phase(isStale:)`). Verificato con l'app chiusa: il passaggio arriva
  puntuale, ma iOS ridisegna una volta sola, quindi senza un altro aggiornamento alla fine della seconda fase il conto
  alla rovescia resta a 0:00. `liveactivitiesd` segna scaduta un'attività non prima di 120 s dall'ultimo aggiornamento
  (visto nei log): nelle prove servono fasi più lunghe di 2 minuti. L'attività finisce solo se l'app gira dopo
  l'ultima lezione (altrimenti la chiude iOS dopo 8 ore).
- Avvio programmato (iOS 26, `request(…start:)` con `alertConfiguration` obbligatoria): il prossimo giorno di scuola
  (e oggi, prima della finestra) resta `pending` e parte da solo all'ora indicata anche con l'app chiusa, con un avviso
  (materia, ora, aula). Verificato: parte con ~2 s di ritardo e iOS apre l'app in background ("Activity started"),
  che subito allinea il contenuto. Un'attività in attesa con un altro inizio (orario cambiato) viene rifatta
  (`scheduledStart` negli attributi).
- Avvio e fermata: Impostazioni › Orario › "Attività in diretta" (`Preferences.liveActivities`, di serie sì, solo su
  questo dispositivo); pulsante a icona nella `TimetableNowCard` (pieno quando è in corso). Fermata a mano o tolta
  dalla schermata di blocco, quel giorno non riparte da sola (`liveActivityStoppedDay`); avviata a mano resta anche
  senza avvio automatico. Senza permesso (`areActivitiesEnabled`) l'interruttore è spento e c'è il collegamento alle
  Impostazioni di iOS, il pulsante della card sparisce.
- Viste: schermata di blocco = scheda sul contenitore della superficie con il colore della materia come accento
  (forma con la sigla, etichetta, titolo, aula e docente, tempo, barra con gli orari, pillola della successiva);
  Dynamic Island sempre con i ruoli scuri: compatta = forma con l'iniziale e tempo, minima = anello di avanzamento con
  l'iniziale, espansa = etichetta e posizione ai lati della fotocamera, sotto la scheda più compatta. Niente
  `minimumScaleFactor` nell'isola (tagliava invece di rimpicciolire). Sul simulatore la schermata di blocco passa
  sempre `colorScheme` scuro (testo bianco su questo sfondo), anche in tema chiaro: la scheda chiara si vede solo
  nella galleria. `simctl io screenshot` non disegna la Dynamic Island: usare lo screenshot dello strumento del
  simulatore. Dopo due LOCK il simulatore può restare nello schermo sempre acceso (cifre "1:--", i tocchi non lo
  svegliano): un terzo LOCK lo sveglia.
- Altre attività: nessuna. Le verifiche del giorno sono già nella stessa attività; un conto alla rovescia verso una
  verifica di un altro giorno non sta nelle 8 ore di un'attività (c'è il widget "Prossima verifica").
- Prove (solo DEBUG): `-BCWWidgetGallery YES` apre nell'app la galleria dei widget (stesse viste, dimensioni reali) con
  `-BCWWidgetGalleryScheme light|dark`, `-BCWWidgetGalleryLook fullColor|accented|vibrant`,
  `-BCWWidgetGalleryKind timetable|now|agenda|average|nextTest`, `-BCWWidgetGallerySource app|sample|signedOut|empty`
  (stati vuoti) e `-BCWNowMinute N` (i timer seguono comunque l'ora vera). `-BCWWidgetNowLesson YES` sposta gli orari
  dell'istantanea perché la prima lezione di oggi sia cominciata da 20 minuti: così i widget veri mostrano la lezione
  in corso a qualsiasi ora (rilanciare l'app senza l'argomento per tornare ai dati veri).
  `-BCWWidgetGalleryKind live` mostra solo l'attività in diretta (schermata di blocco e isola, tutte le fasi).
- Prove dell'attività (solo DEBUG): `-BCWLiveActivityDemo YES` la avvia con un orario finto attorno a adesso (prima
  lezione tra N secondi, lezioni da 2N, un intervallo da N, verifica alla seconda; `-BCWLiveActivitySeconds N`, 60 di
  serie, almeno 130 per vedere i passaggi a tempo), `-BCWLiveActivityDemoStart S` la programma tra S secondi (poi
  chiudere l'app). La prova resta salvata (`BCWLiveActivityDemoPlan`) finché non finisce, perché iOS riapre l'app
  senza argomenti; il pulsante della card la ferma come quella vera, e `-BCWLiveActivityDemoPlan '()' -liveActivities NO`
  chiude tutto (prima di lasciare il simulatore condiviso: un'attività in attesa parte anche giorni dopo). I messaggi `BCW-LIVE` nella console dicono cosa
  viene richiesto, aggiornato e chiuso. Isola espansa: pressione lunga (`touch_path` di ~1 s) sull'isola con l'app in
  secondo piano. La presentazione minima non si vede sul simulatore: con due attività della stessa app l'isola resta
  compatta (verificato) e non c'è un'altra app con attività (niente Orologio); si vede nella galleria.

## iPad
- Richiesta dell'utente (ottobre 2026): sull'iPad non più l'app dell'iPhone allungata ma un ibrido tra la versione web
  desktop e l'app iOS, con le stesse funzioni. L'iPhone non cambia: tutto ciò che è nuovo dipende da
  `windowClass == .regular` (sempre `.compact` sull'iPhone, anche in orizzontale) o da `WindowClass.isPad` (costante).
- Classe della finestra (`App/WindowLayout.swift`): `regular` = iPad con classe orizzontale regolare e finestra da 700
  punti (si torna `compact` sotto 680); `railExpands` da 1100 (sotto 1080). Le misura `WindowLayoutReader` in `RootView`
  (dopo `overlayHost`, così valgono anche per menu e avvisi), senza animazione. Ambiente: `windowClass`, `railExpands`,
  `pageGutter` (16, 24 in regular, messo da `MainTabView`; lo leggono `pagePadding`, `ChipRow`, `CalendarBar`,
  `TopAppBar`). Nei fogli (`m3Sheet`) tornano `compact` e 16: dentro un foglio si usa il layout del telefono.
- Shell (`MainTabView.shell`): sull'iPhone la `TabView` da sola, come prima. Sull'iPad la `TabView` sta sempre nello
  stesso posto e accanto ci sono, facoltativi, `WideTopBar` e `NavigationRail` (`App/WideShell.swift`): cambiando
  classe o Liquid Glass pile di navigazione, giorni scelti e pagine aperte restano. Il pannello è ritagliato da
  `PanelShape`, che fuori dalla finestra larga senza Liquid Glass non ritaglia nulla (con un raggio 0 tagliava la barra
  delle schede di vetro e gli sfondi nella zona dell'indicatore della Home).
- Sezioni di Tu (`App/AppSection.swift`: titoli, titoli brevi, icone, colori, gruppi e conteggi come
  `sections-meta.js` del web) come `Tab` solo sull'iPad, in `TabSection` con `.tabPlacement(.sidebarOnly)` (anche sul
  gruppo, altrimenti la barra in alto mostrava la freccia ›), dopo Cerca, così gli indici della barra non cambiano.
  Tornando `compact` la sezione aperta passa nella pila di Tu (`AppNavigation.pendingSection`); `openSettings` apre le
  Impostazioni in Tu dalla barra superiore o dalla barra laterale. `-BCWOpenPage <sezione>` in regular sceglie la sezione.
- Senza Liquid Glass, finestra larga (come il web da 840 px): barra superiore (logo, ricerca generale che apre la
  scheda Cerca, X o Esc per tornare alla scheda di prima, Aggiorna, Impostazioni, avatar), barra di navigazione da 96
  punti con le etichette brevi o espansa da 264 con i gruppi e i conteggi (fissa da 1100 se l'utente non l'ha ridotta,
  `railCollapsed`; sotto si apre sopra il pannello con il velo), pagina in un pannello `surface` con angoli `radii.xl`
  su `surfaceContainer`. La barra delle schede di sistema passa a `UITabBarController.Mode.tabBar` (`TabSidebar`):
  con la sola barra laterale nascosta UIKit la riapriva allargando la finestra.
- Con Liquid Glass: `TabView` `.sidebarAdaptable` (barra delle schede in alto, barra laterale con le sezioni),
  intestazione con logo e account (apre il cambio account), in fondo Impostazioni e Aggiorna. Aggiorna non legge
  `isRefreshing`: lì dentro (ospitato da UIKit) qualsiasi lettura dello stato faceva segnalare a SwiftUI un ciclo
  nel grafo degli attributi a ogni apertura della barra laterale (verificato). Le pagine principali in regular hanno
  `.inline`, `toolbar(removing: .title)` e il titolo grande fermo sotto la barra (`GlassPageTitle` in `pageChrome`):
  con la barra delle schede in alto `.inlineLarge` non mostra il titolo e `.large` restava compresso dopo aver acceso
  Liquid Glass dalle Impostazioni (verificato). Nella Dashboard l'avatar sta tra le azioni; giorno in grande e
  "Domani"/"Oggi" stanno nel contenuto come con Material.
- Pagine (`Design/Adaptive.swift`): `widthAtLeast(soglia, isOn:)` misura un `Bool` con isteresi di 24 punti, sempre
  falso fuori da regular; `SplitPage`/`SplitSide`/`splitMainPadding` (colonna laterale con il margine della pagina a
  sinistra e 12 verso la principale; principale con 12 e il margine della pagina, larga al massimo 980, sotto 40),
  `AdaptiveColumns`, `readableWidth`. Ogni pagina ha due disposizioni: affiancata da 792 punti di pagina (spenta sotto
  768), altrimenti quella del telefono con margini da 24. Lo stato resta nella vista, sopra il ramo.
- Dashboard: affiancata = colonna laterale da 380 (settimana o mese fermi in cima, sotto "Nei prossimi giorni", che
  scorre) e il giorno a destra (largo al massimo 760, con il gesto del cambio di giorno, l'aggiornamento e il ritorno
  in cima). In regular "Nei prossimi giorni" c'è anche nella vista Calendario (come il web largo).
- Orario: Lista affiancata come la Dashboard, con `TimetableWeekOverview` (riepilogo della settimana: una riga per
  giorno con lezioni, orario e barrette colorate dei blocchi; sabato e domenica solo con eventi) sotto la settimana.
  Vista Giorno da 700 punti = la settimana (`TimetableTimeline` con più giorni, ore da 52 punti, in una card
  `surfaceContainerLow`; lunedì–venerdì più sabato e domenica se scelti o con eventi), da 1000 con il mese e il
  riepilogo in una colonna da 320. La settimana cambia con l'asse condiviso (`DayPage` con la chiave del lunedì),
  senza scorrimento di lato sulla griglia; "Oggi" sta nella barra (la settimana non ha il giorno in grande) e il
  pulsante della vista dice "Vista Settimana". Le verifiche senza lezione le mostra la griglia (`swipe == nil`). In
  modifica la barra di navigazione resta (M3 vieta la barra degli strumenti con quella in basso, non con quella
  laterale) e le istruzioni dicono che si sposta anche in un altro giorno. Con il titolo fermo non serve lo
  scorrimento fermo della vista Giorno del telefono.
- Prove (solo DEBUG): `-BCWWindowClass compact|regular`, `-railCollapsed YES|NO`, `-BCWFakeWindow 1180x820` (l'app in una
  finestra finta di quella misura, rimpicciolita: con le finestre di iPadOS 26 `requestGeometryUpdate` risponde che
  la modalità delle finestre non consente di cambiare orientamento e `simctl` non ruota il simulatore; ritagliare
  1640 × 1140 px in alto dallo screenshot), `-BCWOrientation landscape|portrait` (funziona sull'iPhone),
  `-BCWScript "5:glass=YES;8:class=compact"` (comandi ai secondi indicati, scritti nella console come `BCW-SCRIPT`:
  `glass`, `tab`, `class=compact|regular|auto`, `orientation`, `sidebar=open|close`, `action=settings|rail|search`,
  e per Dashboard e Orario `next`, `prev`, `scroll`, `top`, `nextweek`, `editing`, `mode`; `notice` apre la prima
  comunicazione nella Bacheca affiancata, `loginmode` e `loginfocus` cambiano modulo e danno il fuoco nell'accesso,
  `timepicker` e `timetyping` aprono il selettore dell'orario e passano ai numeri). Servono quando lo strumento del
  simulatore non ha il permesso di toccare. Un'azione arriva solo alle viste già presenti: aspettare che il foglio sia
  aperto prima della successiva (qualche secondo).
- Controllo dell'iPhone: screenshot prima/dopo (Dashboard, Orario Lista, Giorno e modifica, Voti, Tu, Bacheca,
  Aspetto, con e senza Liquid Glass) identici al pixel tranne la barra di stato; autotest dell'orario e dei widget PASS.
- Seconda finestra dell'iPad: `AppModel.bootstrap()` si fa una volta sola (`didBootstrap`).
- Non verificati: ridimensionamento reale delle finestre e rotazione vera (lo strumento del simulatore non ha avuto il
  permesso; la finestra finta li approssima). Con `-BCWWindowClass compact` e Liquid Glass la barra delle schede resta
  in alto, perché la classe di dimensione vera è ancora regular.
- Voti: affiancati = media (anello da 168) e andamento in una colonna da 380, schede, filtro e voti a destra (larghi al
  massimo 760); in colonna da 640 punti di contenuto media e andamento uno accanto all'altro. Materia: colonna da 360
  con media, periodi e obiettivo, a destra il grafico (alto 240) e i voti.
- Tu: le voci delle sezioni vengono da `AppSection` (titoli, icone, colori, sottotitoli, conteggi) e in regular
  scelgono la sezione nella barra di navigazione (`AppNavigation.select`), anche "Da vedere" e le statistiche delle
  assenze. Affiancata: profilo (320) accanto a statistiche e "Da vedere", gruppi in `AdaptiveColumns(320)`; in colonna
  regular gruppi in `AdaptiveColumns(300)`; sul telefono com'era.
- Bacheca: affiancata come la posta del web: elenco da 380 (ricerca e chip in cima) e la comunicazione scelta in un
  pannello `surfaceContainerLow` con angoli `radii.xl` (`NoticeDetailView(insets:)`, `.id` per comunicazione: si
  segna come letta aprendola), altrimenti "Nessuna comunicazione aperta". Sottotitolo "N da leggere" in regular.
- Impostazioni: affiancate = pannelli in una colonna da 320 (`ListRowButtonStyle(selected:)`, `NavigationRow` senza
  freccia) e il pannello scelto a destra (largo al massimo 640). Il contenuto della pagina Account è `AccountContent`,
  usato anche dal pannello Account. `AppNavigation.settingsPane` sceglie il pannello (`-BCWOpenPage impostazioni-x`
  in regular). Liquid Glass acceso dal pannello Aspetto: la pagina resta (verificato).
- Elenco e dettaglio che si richiudono (Bacheca, Impostazioni): tornando in colonna il dettaglio scelto passa nella pila;
  tornando larghi si chiude da sé (`dismissesWhenSplit`) e ricompare accanto all'elenco. Lo fa il dettaglio, non la
  pagina sotto: una pagina coperta da un'altra nella pila non si ridimensiona e non se ne accorge (verificato).
- Sezioni: Scrutini (riepilogo a sinistra), Anni precedenti (archivio sul web a sinistra), Assenze (contatori, avviso e
  filtri in `FlowLayout` in 340, mesi a destra) e Lezioni (scelta e mese di `CalendarBar(showsDots: false)` o le
  materie in 320, a destra il giorno o le card) affiancate; mesi delle assenze, giorni dell'Agenda (ricerca sulla riga
  del periodo), docenti del Materiale e risultati della ricerca in colonne; Note, Materie e Libri in `readableWidth()`;
  Calendario con le due card affiancate da 640 punti. `CardGrid` è una griglia adattiva in regular.
- Ricerca nelle pagine: in regular il campo è sempre nel contenuto (`PageSearchBar`), anche con Liquid Glass
  (`GlassLocalSearch` mette `.searchable` solo in compact).
- Fogli: `m3Sheet(size: .form | .page)` sull'iPad dà `presentationSizing` e toglie la maniglia; `m3Detents` mette i
  rilevamenti solo sull'iPhone (sull'iPad un rilevamento medio accorciava il foglio lasciandolo in basso). `.page`:
  generatore, verifiche nascoste, palette su una serie, Safari degli anni precedenti; il resto `.form`, anche il cambio
  account (con `.form.fitted` uno `ScrollView` misura troppo poco: restava tagliato). Selettori della data e dell'orario
  (`PickerPresentation`): sull'iPad `.fitted` largo 360; passando ai numeri il foglio non si rimpicciolisce, quindi i
  pulsanti restano in fondo (`Spacer` solo sull'iPad). Il tastierino numerico dell'iPad è un riquadro sopra il campo.
- Accesso: in regular da 760 punti una card `surfaceContainer` (angoli `radii.xli`, larga al massimo 1040) in due
  colonne: logo, titolo e spiegazione del modulo (i due testi sovrapposti, così la card non cambia altezza) con
  `LoginArt(wide:)`, a destra gruppo e modulo; sotto affiliazione e server. Niente disposizione compatta con la
  tastiera. Nei fogli (aggiungere un account, account BCW) resta quella del telefono.
- Attività in diretta solo sull'iPhone (`LiveActivityManager.isSupported`): sull'iPad niente impostazione né pulsante
  nella card "Adesso" (`areActivitiesEnabled` è falso).
- La Dashboard segue la larghezza (titolo abbreviato) solo in compact; in regular la misura resta in un
  `UnobservedValue`.
- Le conversioni delle schede per la finestra stretta (sezione in Tu, ricerca chiusa) valgono solo nel passaggio da
  regular a compact, non all'avvio: all'avvio sull'iPhone toglievano la scheda Cerca di `-BCWTab search`.
- Non verificati a mano (anche nel passo 2 senza permesso di toccare): trascinamenti, file e foto scelti dai fogli
  centrati, QuickLook e l'evento nel Calendario da un foglio; iPad mini e 13 pollici. Il resto è provato con
  `-BCWFakeWindow`, `-BCWWindowClass` e `-BCWScript`.

## Prestazioni
- Eventi, assenze e giorni del calendario per giorno: usare `model.events(on:)`, `absences(on:)`, `calendarStatus(on:)`,
  che leggono indici ricostruiti quando cambiano i dati. Confrontare le date con `isSameDay` su tutto l'elenco è lento
  (il calendario di Foundation dominava i profili) e le celle del calendario lo fanno a ogni aggiornamento.
- Nelle viste calcolare gli elenchi una volta per aggiornamento (`let` nel `body`, o una struttura come
  `DayDetail.Content` e `SearchView.Results`), mai in proprietà calcolate richiamate più volte o dentro le righe.
- Niente `@State` con misure che cambiano di continuo (`onGeometryChange` di un `CGFloat`): ricalcola la pagina a ogni
  fotogramma; misurare solo il passaggio che serve (`Bool`).
- Misure che cambiano a ogni fotogramma e servono solo in certi momenti vanno in
  `UnobservedValue`, non in uno `@State` osservato: altrimenti l'intera pagina si ricalcola a ogni fotogramma.
- Valori osservati che cambiano a ogni fotogramma (es. lo spostamento del dito di `DaySwipe`) si leggono in un
  modificatore piccolo (`DayDragEffect`), non nel corpo del contenitore: lì ogni movimento ricostruiva e
  reimpaginava l'intero giorno (Dashboard con il thread principale sempre occupato trascinando).
- `.card()` mette l'ombra sulla sola forma di sfondo: un'ombra sull'intera vista va ricalcolata dal contenuto.
- Le viste con chiusure tra i parametri (giorni successivi, giorni dell'orario, giorni della barra del calendario)
  sono `Equatable` e usate con `.equatable()`: altrimenti ogni aggiornamento della pagina le ricalcolava tutte.
- Righe con una colonna fissa a sinistra (data, casella) e testo a destra: `LeadingColumnLayout`, non
  `HStack(alignment: .top)`. L'`HStack` misura i figli più volte con larghezze di prova e, con testi su più righe e
  righe annidate, il cambio di giorno della Dashboard passava quasi tutto il tempo lì ("Nei prossimi giorni").
- Animazioni continue (che non finiscono mai) con Core Animation, non con `TimelineView(.animation)`: quella
  aggiorna la vista a ogni fotogramma finché si vede. L'onda di `WavyProgress` è un `CAShapeLayer` animato
  (`MovingWave`): con la lezione in corso l'Orario fermo teneva occupato il thread principale per circa un quinto
  del tempo, ora quasi zero.
- Per misurare: build Release per il simulatore con `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG`, un aggancio temporaneo
  che ripete l'interazione e `sample <pid> 8` sul processo del simulatore, poi sommare i campioni per funzione dell'app.
  L'impaginazione finisce sotto chi chiede per primo una misura (il `primaryMinimum` di un `safeAreaInset`, il
  `GeometryReader` di `WavyProgress`): lì non è lavoro doppio, le misure dopo usano la cache. Il simulatore condiviso
  con altre compilazioni dà numeri molto variabili (anche 30–60% per la stessa build): confrontare più giri.

## Sistema di design (Material 3 Expressive, `BCW/Design/`)
- `ThemeStore.shared` (`@Observable`): preferenze di Aspetto (accento, stile dei colori, contrasto, angoli, movimento,
  testo arrotondato, `liquidGlass`) e ruoli di colore. Le viste che leggono `Theme.x` si aggiornano da sole.
  I colori si generano come sul web: JavaScriptCore esegue `Resources/Scripts/material-color-utilities.js` e
  `bcw-theme.js` (`BCWTheme.build`/`swatch`), risultato in cache in UserDefaults (`themeCache`). In `init` non
  configurare le barre di sistema (ricorsione su `ThemeStore.shared` → crash all'avvio).
- Font: `Resources/Fonts/GoogleSansFlex.ttf` (assi wght, opsz, ROND via CoreText), `Font.m3(size, weight:)`,
  `Font.m3(role)`, `Font.numeral`. Icone: Material Symbols Rounded come SVG template `m.<nome>` in
  `Assets.xcassets/Material` (`Icon`, `Image.m`, `Label(_:icon:)`). Forme: `MaterialShape`/`Shaped`, `LoadingIndicator`.
- Componenti: `Controls.swift` (`.m3(...)` pulsanti, `IconButton`, `FAB`, `SegmentedButtons`, `FilterChip`, `Pill`,
  `M3ToggleStyle`, `M3Stepper`, `M3SearchBar`), `Lists.swift` (`ListGroup` con angoli per cella, `ListRow`,
  `ToggleRow`, `SelectRow`, `NavigationRow`, `FormField`/`FormFieldValue` per i campi con l'etichetta sopra come nei
  fogli del web…), `Overlays.swift` (`.overlayHost()`: menu `AppMenu`/`MenuItem`,
  `.m3Dialog`, toast; con Liquid Glass i menu sono `Menu` di sistema), `Page.swift`.
- Selettore della data (`DatePicker.swift`, `M3DatePickerSheet`): modale di Material 3 con la data in grande,
  griglia del mese (scorrendo di lato si cambia mese) e griglia di mesi e anni; Oggi, Annulla, OK. Lo apre anche
  `DateField` (pillola con la data, `Controls.swift`; riporta nel suo `range` la data scelta).
- Selettore dell'orario (`DatePicker.swift`, `M3TimePickerSheet`): modale di Material 3 a 24 ore, ore e minuti in due
  riquadri e quadrante (ore su due anelli, fuori 0–11 e dentro 12–23; scelta l'ora si passa ai minuti), con l'icona
  della tastiera per scriverli. Lo apre `TimeField` (editor degli eventi, generatore, intervalli).
- Niente controlli di sistema invisibili sopra un campo (`DatePicker`, `ColorPicker` con opacità quasi zero): non si
  aprivano più al tocco e se ne intravedeva il testo. Un pulsante apre un foglio (selettori di Material 3; per il
  colore d'accento qualsiasi `UIColorPickerViewController` in `SettingsView`).
- Login (`LoginView`): con la tastiera aperta la disposizione è compatta e in alto, con logo piccolo e titolo su una
  riga, il gruppo Classeviva/Account BCW, campi e "Accedi"; "Prova la demo" e le note tornano chiudendo la tastiera.
  La disposizione segue la tastiera visibile (notifiche di UIKit), non il campo attivo: cambiando modulo con la
  tastiera aperta il cursore passa al campo corrispondente (al giro dopo) e la tastiera resta. Un tocco nello spazio
  vuoto la chiude. Le note in basso occupano sempre l'altezza delle più lunghe tra i due moduli (copie nascoste in uno
  `ZStack` allineato in alto): cambiando Classeviva/Account BCW il resto, centrato, non si sposta.
  Nella disposizione compatta logo e titolo sono centrati sulle maiuscole (allineamento `capCenter`, verificato
  al pixel): con le linee di base allineate il titolo, più piccolo, stava in basso.
- Componenti propri di M3 Expressive (`Expressive.swift`): `SearchAppBar`, `AccountAvatarButton`, `FABMenu` (con
  Liquid Glass `GlassFABMenu`: pulsante di vetro tinto di 60 punti, come il pulsante di ricerca della barra delle
  schede e allineato sopra di esso, da cui escono le voci come pillole di vetro con `glassEffectID` nello stesso
  `GlassEffectContainer`. Non un `Menu` di sistema: chiudendosi, il vetro scuro del menu rientrava senza tinta (nero
  fino alla fine). Né `glassEffect(.interactive())` né `.buttonStyle(.glassProminent)` si allungano trascinando in
  SwiftUI (crescono soltanto): limite accettato dall'utente, niente allungamento fatto a mano. Non può fondersi con la
  barra delle schede di sistema, il cui vetro non sta nello stesso `GlassEffectContainer` delle viste dell'app), `FloatingToolbar` (vivace = modalità temporanea; con Liquid Glass
  in vetro) con `ToolbarIconButton`/`ToolbarTextButton`, `PrimaryTabs`, `ConnectedButtonGroup` (etichette libere),
  `SegmentedSection` (intestazione comprimibile + `ListGroup`) con `SegmentCell`, `StatusChip`, `DateBadge`, `TabChrome`
  (una pagina nasconde la barra delle schede: modifica dell'orario, ricerca; va rimesso a `false` in `onDisappear`).
  Linee guida M3: la barra degli strumenti non va insieme alla barra di navigazione, per questo in modifica la barra
  delle schede sparisce; il menu del FAB ha 2–6 voci.
- Pagine: `pageChrome(title, …) { azioni }`. Con Liquid Glass usa titolo e barra di sistema (`.inlineLarge` per le
  pagine principali, `isRootPage`); con Material nasconde la barra e mette `TopAppBar` + titolo grande nel contenuto.
  Fogli: `sheetChrome` + `.m3Sheet()`, con gli angoli del sistema: `presentationCornerRadius` vale anche per gli
  angoli in basso, che così non seguivano più la curva dello schermo. `MainTabView`: con Material la `M3NavigationBar` è sovrapposta (TabView e
  NavigationStack non propagano `safeAreaInset`), lo spazio in fondo arriva con `bottomBarInset`.
- `ListGroup`: prima e ultima voce con angoli ampi (`li`), quelle in mezzo stretti (`xs`). Gli angoli vanno passati
  anche direttamente allo sfondo della voce: un modificatore applicato a un `Subview` fuori da `.environment` legge
  ancora i valori dell'ambiente esterno (prima tutte le voci avevano gli angoli ampi).
- Colore d'accento dei componenti UIKit (barra delle schede, pulsanti e menu di sistema, avvisi): `Theme.applyTint()`
  dà alle finestre il `primary` del tema, a ogni cambio di aspetto e all'avvio (`RootView.task`). Nel catalogo non c'è
  più `AccentColor` (era il vecchio rosso-arancio, che compariva con Liquid Glass): non rimetterlo.
- Barra delle schede di sistema (Liquid Glass): etichette con `Tab(value:content:label:)` e sempre l'icona vuota;
  quella piena (`AppTab.selectedIcon`) è la `selectedImage` degli elementi della `UITabBar` (`TabBarSelectedImages`),
  così segue la bolla mentre la si trascina, come nelle app di sistema (verificato). Scegliendo l'icona
  nell'etichetta in base alla scheda aperta cambiava solo a selezione avvenuta.
- Indietro scorrendo: con Liquid Glass c'è il gesto di sistema da qualsiasi punto del contenuto (iOS 26). Con la barra
  nascosta (Material) UIKit spegne sia quello dal bordo (riattivato dal delegato in `Page.swift`) sia quello dal
  contenuto (che resta spento anche cambiandone il delegato: non viene nemmeno interpellato). Lo sostituisce
  `ContentPopGesture`, un pan sul contenitore della pila che guida la stessa transizione di sistema
  (`handleNavigationTransition:` del delegato del gesto di sistema), attivo solo con la barra nascosta e con una pagina
  a cui tornare; gli scorrimenti orizzontali che possono ancora andare verso sinistra hanno la precedenza.
- Sul simulatore i tocchi istantanei spesso non premono i pulsanti SwiftUI: usare `touch_path` da 120–150 ms.

## Icona dell'app
- Richiesta dell'utente (ottobre 2026): Impostazioni › Aspetto › Icona dell'app (`AppIconSettingsView`, dalla voce
  `AppIconSettingsLink`) sceglie forma, colore, aspetto e sfondo scuro. La barra del logo (pillola 64 × 8,73, come
  `bcw-linea.svg`) sta al centro di una forma di Material larga l'86% della tela; la barra è larga il 77% della forma
  (`AppIconGeometry`). Un solo disegno, `AppIconArtwork`, per anteprima, celle e generatore: sono identici.
- iOS non disegna icone mentre l'app gira: ogni combinazione è un'icona alternativa piatta in
  `Resources/AppIcons.xcassets` (scelta dell'utente: un'icona a livelli pesa circa 4 MB compilata, una piatta circa
  100 KB). Un `.appiconset` per combinazione con tre PNG 1024: `chiara`, `scura` (luminosity dark), `colorata`
  (luminosity tinted). `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` (pbxproj e `project.yml`) le mette
  tutte nel pacchetto e nell'Info.plist.
- Nomi: `AppIcon-<forma>-<colore>-<variante>` e `AppIcon-classica-<variante>` (`AppIconChoice.assetName`). Varianti
  (`AppIconVariant`, da Aspetto e Sfondo scuro): `auto`, `autoios`, `chiaro`, `scuro`, `scuroios`. La combinazione
  predefinita (cerchio, Mattone, auto, Material) non ha un `.appiconset`: è `AppIcon.icon`, a lastre di vetro vere,
  e si applica con `setAlternateIconName(nil)`.
- 8 forme (`AppIconShape`: circle, cookie4, cookie6, cookie9, clover4, clover8, sunny, gem; cookie4, cookie6 e
  clover4 ruotate perché i lobi stiano ai lati della barra, e rimpicciolite se ruotando escono dal riquadro della
  forma: il quadrifoglio arrivava al 94% della tela) più la classica (solo barra su crema, l'icona fino alla
  3.1), 10 colori (`accentPresets`), 5 varianti: 404 icone. Scartate square, pentagon, arch, cookie12 e simili: con 12
  forme il catalogo cresceva di circa 63 MB.
- Colori (Tonal Spot, contrasto standard, `AppIconPalette`; Ardesia con Neutral, perché Tonal Spot dà a tutti i
  primari lo stesso croma e Ardesia diventava uguale a Blu): chiara = sfondo surface, forma primary, barra on-primary
  (la forma si stacca dallo sfondo anche in piccolo; surface-container-low + primary-container era troppo tenue);
  scura = surface-dim, primary-container e primary del tema scuro; `autoios` = le stesse forma e barra su sfondo
  trasparente, iOS ci mette il suo scuro; `scuroios` con le icone chiare = sfumatura #2E2E30 → #111112 come lo scuro
  di iOS; colorata = sfondo trasparente, forma grigio 0,3, barra bianca (con 0,45 iOS schiariva la forma quasi al
  bianco). Tema dell'app: `AppIconColor.nearest(to:)` sceglie il colore proposto più vicino per tonalità e croma HCT
  (croma contato fino a 36: i colori quasi grigi vanno su Ardesia).
- Rigenerare dopo aver cambiato forme, colori o disegno: compilare, installare e lanciare
  `xcrun simctl launch --console-pty <udid> com.bcw-classeviva.app -BCWGenerateAppIcons <percorso assoluto di BCW/Resources>`
  (solo DEBUG, `AppIconGenerator`): riscrive da capo `AppIcons.xcassets` e `AppIcon.icon` (SVG della forma e della
  barra, `icon.json`) e stampa `BCW-APPICONS OK 404`; poi ricompilare. I PNG sono a tavolozza (in media 13 KB). Il
  generatore è deterministico: con un percorso di prova al posto di `BCW/Resources` i file escono identici a quelli
  del repository, un modo rapido per controllare che il catalogo corrisponda al codice.
- `AppIconController` (avviato in `RootView`) cambia l'icona solo se cambia il nome e con l'app attiva: le scelte
  della pagina dopo 1 s; i cambi del solo accento con "Tema dell'app" aspettano l'uscita da Impostazioni › Aspetto
  (`holdThemeChanges`), così provando i colori iOS mostra un solo avviso; tornando nell'app con Aspetto aperta il
  controllo si fa all'uscita. Errori in un toast (`AppIconFailureReporter`). Ogni richiesta a iOS (cioè ogni avviso)
  scrive `Cambio d'icona: <nome>` nel registro (sottosistema `com.bcw-classeviva.app`, categoria `AppIcon`).
  `AppIconColor.nearest` ricorda l'ultimo risultato in UserDefaults (`appIconNearest`): calcolarlo carica
  JavaScriptCore, che all'avvio con un accento qualsiasi altrimenti non serve.
- Sincronizzazione: `appIconShape`, `appIconColor`, `appIconAppearance`, `appIconDarkBackground` in
  `ThemeStore.syncedValues`/`applySynced` (valori sconosciuti ignorati). In `CloudSync.syncSettings` una chiave che
  l'ultima sincronizzazione non conosceva conta come cambiata solo se il server non ce l'ha: così il valore
  predefinito di un dispositivo appena aggiornato non cancella la scelta fatta su un altro.
- Peso misurato: `Assets.car` da 5,05 MB (ramo claude) a 49,1 MB, +44 MB, metà iPhone e metà iPad; per un solo
  iPhone (actool con `--filter-for-device-model iPhone18,3`, come lo sfoltimento dell'App Store) da 2,6 a 24,6 MB.
  Ogni icona compilata tiene solo le tre immagini 1024 (circa 54 KB per dispositivo). `compression-type` nei
  `Contents.json` non cambia nulla: actool salva sempre le icone in ARGB con lzfse.
- Verificato sulla Home del simulatore (iOS 26.3, Default/Dark/Clear/Tinted): icona principale a vetro, alternative,
  classica, Sempre chiaro e Sempre scuro, sfondo scuro Material e iOS; con "Tema dell'app" provando più accenti in
  Aspetto (anche dopo aver cambiato Liquid Glass nella pagina) l'icona cambia una volta sola, uscendo dalla pagina;
  tre forme toccate di seguito danno una sola richiesta.
- Limiti verificati: iOS aggiunge i suoi riflessi di vetro anche alle icone piatte (sfumatura sulla forma, alone sulla
  barra). Con le icone colorate e trasparenti iOS tinge sempre l'immagine colorata, anche con Sempre chiaro o Sempre
  scuro: non si può forzare. Sul simulatore (iOS 26.3) l'avviso del cambio non si apre ("couldn't load upcall bundle
  principal class"): l'icona cambia ma `setAlternateIconName` risponde con un errore di I/O (il controllore lo
  riconosce da `alternateIconName`) e i cambi successivi falliscono ("couldn't make icon alert token", EAGAIN) finché
  non si riavvia lsd: `xcrun simctl spawn <udid> launchctl stop com.apple.lsd`. Le modalità delle icone di iOS si
  cambiano dalla Home: pressione lunga, Modifica, Personalizza.

## Convenzioni
- Testi UI e commenti in italiano. Stile: liste segmentate, `StatusChip`, `FilterChip`, `StatTile` (anche in griglie
  collegate con `corners`), `GradeBadge`, `AverageRing`,
  `Pill` (stati su una riga, con versione abbreviata).
- Animazioni: solo le molle di `Motion` (valori di `MotionScheme` di M3 Expressive) e le transizioni di Material 3 in
  `Motion.swift`: `.sharedAxisX/Y` (elementi allo stesso livello: giorni, schede dei Voti), `.fadeThrough` (contenuti
  senza relazione: ricerca, Lista/Giorno), `.expand` (sezioni). Niente curve o molle fatte a mano.
- Sezioni comprimibili: sempre `CollapsibleContent` (espansione M3: il contenitore si allunga con la molla, il
  contenuto compare in dissolvenza ed è ritagliato) e intestazione con `HeaderButtonStyle`, dentro
  `withAnimation(Motion.spatial)`. Da chiusa il contenuto non viene costruito; lo stato interno (es. una riga espansa)
  si azzera chiudendo la sezione.
- Titoli senza Liquid Glass: le pagine principali delle schede hanno il titolo grande (34 punti) nella riga dei
  pulsanti, come `.inlineLarge` con Liquid Glass (`TopAppBar(large:)`, in `pageChrome` quando non c'è la freccia
  indietro). Dashboard e Orario hanno inoltre il giorno in grande sotto la settimana.
- Pagine lunghe (Tu, Account, Impostazioni): margine in fondo `Theme.bottomInset`. iOS rimpicciolisce la tab bar
  scorrendo solo se la pagina è abbastanza lunga (verificato: Tu con 24 punti non lo faceva, con 120 sì).
- README: niente trattini lunghi, niente grassetto/corsivo nelle parti aggiunte, tabelle solo se indispensabili.
- Non usare nero/bianco puri come sfondo; usare sempre i colori di `Theme`.
