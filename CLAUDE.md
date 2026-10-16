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
  backup esportabile/importabile (due conferme) e iCloud segnato come Work in progress nelle Impostazioni.
  "Modifica orario" (menu in alto a destra) apre la modifica grafica, sempre nella vista Giorno: spostare e
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

## Stato attuale
- Il progetto compila e gira sul simulatore. `xcode-select` punta ai Command Line Tools, quindi per compilare da
  terminale serve `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project BCW.xcodeproj -scheme BCW -destination 'platform=iOS Simulator,name=iPhone 17' build`
- macOS non è più supportato in modo nativo (scelta dell'utente, ottobre 2026): niente codice, impostazioni o
  `#if os(macOS)` per il Mac.
- Per provare le modifiche visive usare "Prova la demo" (`DemoServer.swift`). Si avvia anche con l'argomento
  `-demoMode YES`.
- Argomenti di avvio per le prove (solo DEBUG, con `simctl launch … <argomenti>`): `-BCWTab timetable|grades|you|search`
  apre una scheda, `-BCWLiquidGlass YES|NO`, `-BCWAccent #RRGGBB`, `-BCWTimetableDemo YES` crea l'orario della demo
  dalle lezioni se è vuoto, `-BCWHideTests YES` aggiunge una regola e una verifica nascosta,
  `-BCWTimetableSheet generator|hidden` apre il generatore (con `-BCWGeneratorBreaks N` intervalli) o le verifiche
  nascoste, `-BCWTimetableDraft YES` mostra la bozza in anteprima, `-timetableMode list|day` sceglie la vista,
  `-BCWTimetableEditing YES` apre la modifica, `-BCWTimetableDay N` apre l'orario N giorni dopo oggi (i valori negativi
  non passano come argomenti), `-BCWOpenSubject YES`, `-BCWDaysAgo N`, `-BCWKeychainService nome` (Portachiavi vuoto).
- Autotest dell'orario (solo DEBUG): `-BCWTimetableSelfTest YES` prova backup (esportazione, importazione, file,
  rifiuto di file non validi, riapertura da disco), modifiche estese agli eventi con lo stesso nome, generazione e
  passaggio dall'allineamento libero all'automatico;
  stampa `BCW-SELFTEST PASS/FAIL` ed esce. Sul simulatore: `simctl launch --console-pty booted com.bcw-classeviva.app
  -demoMode YES -BCWTimetableSelfTest YES`.
- Simulatori: sono disponibili iOS 26.3 e iOS 27. Lo strumento del simulatore di Claude Code (tocchi, pressioni lunghe,
  screenshot) funziona con il simulatore acceso; per le animazioni registrare con `simctl io … recordVideo`. Quello di iOS 27 appena avviato satura la CPU per minuti e fa
  bloccare `simctl install/launch`: tenerne acceso uno alla volta.

## Architettura
- `BCW.xcodeproj` usa **cartelle sincronizzate** (objectVersion 77): i file in `BCW/` entrano nel target da soli.
- Un solo target iOS (iPhone e iPad; `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`).
- `Utilities/Platform.swift`: piccoli adattatori (`Platform.copy`, `screenTitle`, `pagePadding`, `CardGrid`, `ChipRow`,
  `PlatformNavigationStack`, `localSearchable`, `CenteredCircle`, `UnobservedValue`).
- iOS, ricerca: `.searchable` sta dentro la scheda Cerca (`SearchView`), con `Tab(role: .search)`. Con l'SDK di
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
  `AccountsSection` della pagina Account; si apre dal pulsante in alto a destra in Tu e tenendo premuta la scheda Tu, e
  si chiude da solo quando comincia il cambio. La demo non è un
  account: non entra nel conteggio (icona del pulsante, testi), si apre con "Prova la demo" anche con un account
  collegato (`activeAccountID` resta impostato e uscendo si torna a quello).
- Cambio di sessione (altro account, demo, uscita dalla demo verso un account, rimozione dell'account attivo, account
  aggiunto ad app aperta): `AppModel.changeSession` sfuma l'interfaccia (`isChangingSession`, opacità in `RootView`),
  cambia i dati senza animazioni mentre non si vede e la fa riapparire quando ci sono i dati (subito con la cache,
  altrimenti a fine aggiornamento, al massimo 3 s). Così niente si ridimensiona davanti all'utente.
- `project.yml` è un'alternativa per XcodeGen.
- Icona: `Resources/AppIcon.icon` (Icon Composer, con varianti chiara/scura/tinta), il cui
  nome corrisponde a `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Nel catalogo `Assets.xcassets` non c'è più
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
- Orario: solo viste Lista e Giorno (`TimetableMode.available`; il mese c'è nella Dashboard).
- Calendario mobile su iPhone (`Components/CalendarHeader.swift`), uguale in Orario (Lista e Giorno) e Dashboard
  (Lista = settimana, Calendario = mese): `CalendarHeader` galleggia sopra l'area che scorre in uno `ZStack` e non fa
  parte dello scorrimento. L'area parte sotto il calendario ridotto (`safeAreaPadding` costante) e scende di `range`
  (intero − ridotto; nel mese dipende dalle settimane) con `.offset` (`WeekHeaderScroll.Shift`, solo disegno).
  Il passaggio non usa lo scorrimento di iOS: `CalendarHeaderPan` aggiunge allo `UIScrollView` (trovato dallo sfondo del
  contenuto) un pan verticale, che parte sempre da intero (l'area è ferma, `scrollDisabled`; in Dashboard
  `expandedScrolls` lascia allo scorrimento i gesti verso il basso, per aggiornare), da ridotto solo verso il basso con
  l'area in cima e sempre durante uno scatto; e uno orizzontale per il giorno prima/dopo (`onSwipeDay`, solo da
  fermo): il giorno accanto (`SwipeDayPages`, nel contenuto dello scorrimento, che ha `scrollClipDisabled`; le pagine hanno un'identità propria e un giorno fisso, i giorni accanto si costruiscono in anticipo da fermi e al rilascio le pagine si scambiano di ruolo senza essere ricostruite: costruire una pagina della Dashboard costa ~80 ms)
  segue il dito già durante il gesto. Al rilascio il giorno cambia subito (vibrazione e dissolvenza nel calendario:
  `CalendarHeader` riattiva l'animazione con `.transaction(value:)`) e i due contenuti si scambiano di ruolo nella stessa
  posizione, senza animazioni (il nuovo diventa quello principale, il vecchio quello accanto); poi scorrono fino al
  giorno nuovo. Un gesto durante lo scorrimento lo riprende da dov'è. "Oggi"/"Domani" nella barra
  seguono il giorno con uno stato a parte animato (`showsToday`, `showsTomorrow`), perché lo scambio è senza animazioni.
  La vibrazione del punto di resistenza scatta anche quando lo supera solo la velocità del rilascio. Lo scorrimento li aspetta (`shouldBeRequiredToFailBy`); misure nella finestra; la traslazione
  riparte da zero quando il gesto è riconosciuto (altrimenti il contenuto saltava dei punti di riconoscimento).
  Il contenuto segue il dito con una curva di resistenza (`resisted`): prima del punto (metà del tratto) resta sempre
  più indietro, superato lo rincorre (`catchUp`) con una vibrazione ed è tirato verso l'altra posizione. Un gesto che
  riprende uno scatto a metà segue il dito senza curva. In un gesto si arriva al massimo a ridotto. Lasciando il dito
  decide il lato del punto (con la velocità) e una molla calcolata a ogni fotogramma (`CADisplayLink`, così un gesto
  la riprende dal valore visibile) porta alla posizione senza superarla. Lasciare allo scorrimento un gesto durante
  la molla lo faceva tremare (si muove con l'area): non farlo. L'avanzamento si legge solo negli host del calendario
  e in `Shift`. Tutto è tagliato solo dal bordo della card (`scrollClipDisabled`, niente `clipped` interni); da ridotto
  le griglie invisibili non devono prendere i tocchi (`allowsHitTesting`), altrimenti rubano i gesti all'area.
  Il mese si riduce alla settimana del giorno scelto: le altre settimane salgono e svaniscono, i giorni dei mesi
  accanto che la completano compaiono (`MonthMorphCell`), e riducendo si torna al mese del giorno scelto.
  `CalendarHeaderPan` cerca lo scorrimento a ogni spostamento nella gerarchia (`Anchor`, `didMoveToWindow`/
  `didMoveToSuperview`), non solo in `updateUIView`: quando la pagina viene ricostruita (es. cambiando Liquid Glass)
  i gesti restavano sul vecchio scorrimento, con l'Orario bloccato (`scrollDisabled` da intero) e l'intestazione
  della Dashboard ferma. Un gesto tolto a metà viene chiuso a mano (`detach`).
  Le registrazioni del simulatore salvano fotogrammi solo quando lo schermo cambia (le pause spariscono): per misurare
  un'animazione stampare i valori con l'ora (`CACurrentMediaTime`).
- Impostazioni: elenco di sottopagine (Generale, Aspetto, Voti, Dashboard, Orario, Notifiche, Account).
- Dashboard, "Nei prossimi giorni": ogni giorno è una card comprimibile (`UpcomingDayCard`, intestazione = comprimi).
  Toccando il resto della card si va a quel giorno, ma i tocchi propri vincono: la casella del compito e il testo
  tagliato di una riga (che si apre); `AgendaEventRow.onPlainTap` misura se il testo è tagliato.
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
- Orario, barra: niente frecce per cambiare giorno; "Oggi" compare solo se il giorno scelto non è oggi,
  come "Domani" nella Dashboard.
- Elenchi di card in `CardGrid` (una colonna); filtri in `ChipRow` (scorrono in orizzontale).
- Dashboard: "Nei prossimi giorni" cambia identità (`upcomingGeneration`) in `select(_:)`, insieme al giorno.
  L'identità non deve dipendere dallo stato compresso: comprimere sostituirebbe la sezione intera e l'intestazione
  scenderebbe e risalirebbe. La transizione usa lo spostamento del giorno scelto (`upcomingTransition`,
  `dayDetailHeight`): `.move(edge:)` sposta di tutta l'altezza della vista, troppo con la lista aperta e troppo poco
  con la sola intestazione.
- Rotelle in pulsanti e righe: `InlineProgress`.

## Prestazioni
- Eventi, assenze e giorni del calendario per giorno: usare `model.events(on:)`, `absences(on:)`, `calendarStatus(on:)`,
  che leggono indici ricostruiti quando cambiano i dati. Confrontare le date con `isSameDay` su tutto l'elenco è lento
  (il calendario di Foundation dominava i profili) e le celle del calendario lo fanno a ogni aggiornamento.
- Nelle viste calcolare gli elenchi una volta per aggiornamento (`let` nel `body`, o una struttura come
  `DayDetail.Content` e `SearchView.Results`), mai in proprietà calcolate richiamate più volte o dentro le righe.
- Niente `@State` con misure che cambiano di continuo (`onGeometryChange` di un `CGFloat`): ricalcola la pagina a ogni
  fotogramma; misurare solo il passaggio che serve (`Bool`).
- Misure che cambiano a ogni fotogramma e servono solo in certi momenti (es. `dayDetailHeight`) vanno in
  `UnobservedValue`, non in uno `@State` osservato: altrimenti l'intera pagina si ricalcola a ogni fotogramma.
- `.card()` mette l'ombra sulla sola forma di sfondo: un'ombra sull'intera vista va ricalcolata dal contenuto.
- Su iPhone `-BCWSwipeBench N` / `-BCWHeaderBench N` (solo DEBUG) simulano scorrimenti laterali o riduzioni del calendario
  e stampano i fotogrammi lenti (`BCW-BENCH`); `-BCWTab timetable` apre l'Orario. Le viste con chiusure tra i parametri
  (righe dell'agenda, giorni successivi, giorni dell'orario) sono `Equatable` e usate con `.equatable()`: altrimenti ogni
  aggiornamento della pagina le ricalcolava tutte. Nel mese che si riduce i giorni si spostano con `offset` invece di
  cambiare il margine (che faceva rimisurare tutte le pagine dei mesi a ogni fotogramma).
- Per misurare: build Release per il simulatore con `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG`, un aggancio temporaneo
  che ripete l'interazione e `sample <pid> 8` sul processo del simulatore, poi sommare i campioni per funzione dell'app.

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
- Pagine: `pageChrome(title, …) { azioni }`. Con Liquid Glass usa titolo e barra di sistema (`.inlineLarge` per le
  pagine principali, `isRootPage`); con Material nasconde la barra e mette `TopAppBar` + titolo grande nel contenuto.
  Fogli: `sheetChrome` + `.m3Sheet()`. `MainTabView`: con Material la `M3NavigationBar` è sovrapposta (TabView e
  NavigationStack non propagano `safeAreaInset`), lo spazio in fondo arriva con `bottomBarInset`.
- `ListGroup`: prima e ultima voce con angoli ampi (`li`), quelle in mezzo stretti (`xs`). Gli angoli vanno passati
  anche direttamente allo sfondo della voce: un modificatore applicato a un `Subview` fuori da `.environment` legge
  ancora i valori dell'ambiente esterno (prima tutte le voci avevano gli angoli ampi).
- Colore d'accento dei componenti UIKit (barra delle schede, pulsanti e menu di sistema, avvisi): `Theme.applyTint()`
  dà alle finestre il `primary` del tema, a ogni cambio di aspetto e all'avvio (`RootView.task`). Nel catalogo non c'è
  più `AccentColor` (era il vecchio rosso-arancio, che compariva con Liquid Glass): non rimetterlo.
- Barra delle schede di sistema (Liquid Glass): etichette con `Tab(value:content:label:)` e icona piena per la scheda
  aperta (`AppTab.selectedIcon`), come la barra Material.
- Indietro scorrendo: con Liquid Glass c'è il gesto di sistema da qualsiasi punto del contenuto (iOS 26). Con la barra
  nascosta (Material) UIKit spegne sia quello dal bordo (riattivato dal delegato in `Page.swift`) sia quello dal
  contenuto (che resta spento anche cambiandone il delegato: non viene nemmeno interpellato). Lo sostituisce
  `ContentPopGesture`, un pan sul contenitore della pila che guida la stessa transizione di sistema
  (`handleNavigationTransition:` del delegato del gesto di sistema), attivo solo con la barra nascosta e con una pagina
  a cui tornare; gli scorrimenti orizzontali che possono ancora andare verso sinistra hanno la precedenza.
- Sul simulatore i tocchi istantanei spesso non premono i pulsanti SwiftUI: usare `touch_path` da 120–150 ms.

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
