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
  `-BCWOpenSubject YES` per aprire in Voti la materia con il nome più lungo, cioè una pagina aperta da un'altra;
  `-BCWTimetableDemo YES` crea l'orario della demo dalle lezioni se è vuoto, `-BCWHideTests YES` aggiunge una regola
  e una verifica nascosta, `-BCWTimetableSheet generator|hidden` apre il generatore (con `-BCWGeneratorBreaks N` intervalli)
  o le verifiche nascoste (i fogli si salvano come `<sezione>-<larghezza>-sheet.png`), `-BCWTimetableDraft YES` lo mostra in
  anteprima, `-timetableMode list|calendar|day` sceglie la vista, `-BCWTimetableEditing YES` apre la modifica, `-BCWTimetableDay N` apre l'orario N giorni dopo oggi; i
  valori negativi non passano come argomenti, usare quelli positivi);
  `-BCWScroll N` (con `-BCWWheel YES` come una rotella vera) scorre la pagina prima della foto,
  `-BCWSearchClickAway YES` (con `-BCWSearch`) prova il clic su un risultato e su un'area vuota,
  `-BCWResizeBench YES` misura il ridimensionamento della finestra (tempo per passo, passaggi lenti),
  `-BCWResizeToggle N` passa N volte da due colonne a una (per `sample`),
  `-BCWKeychainService nome` usa un Portachiavi vuoto (con `-demoMode NO` mostra l'accesso: `login.png`);
  le immagini finiscono in `~/Library/Containers/com.bcw-classeviva.app/Data/tmp/BCWSnapshots` (o in `-BCWSnapshotDir`
  con un build senza sandbox, `ENABLE_APP_SANDBOX=NO`) e l'app si chiude da sola. Per ogni immagine stampa anche gli
  elementi della barra della finestra con la loro posizione (`BCWToolbar …`): con lo schermo bloccato le immagini escono
  bianche, ma l'elenco resta affidabile.
- Autotest dell'orario (solo DEBUG): `-BCWTimetableSelfTest YES` prova backup (esportazione, importazione, file,
  rifiuto di file non validi, riapertura da disco), modifiche estese agli eventi con lo stesso nome, generazione e
  passaggio dall'allineamento libero all'automatico;
  stampa `BCW-SELFTEST PASS/FAIL` ed esce. Si lancia l'eseguibile del Mac direttamente.
- Simulatori: sono disponibili iOS 26.3 e iOS 27. Lo strumento del simulatore di Claude Code (tocchi, pressioni lunghe,
  screenshot) funziona con il simulatore acceso; per le animazioni registrare con `simctl io … recordVideo`. Quello di iOS 27 appena avviato satura la CPU per minuti e fa
  bloccare `simctl install/launch`: tenerne acceso uno alla volta.

## Architettura
- `BCW.xcodeproj` usa **cartelle sincronizzate** (objectVersion 77): i file in `BCW/` entrano nel target da soli.
- **Un solo target multipiattaforma** (iOS + macOS nativo, non Catalyst; `SUPPORTED_PLATFORMS`, `SDKROOT = auto`).
  Su macOS: sandbox con rete in uscita e Calendario (impostazioni `ENABLE_*[sdk=macosx*]`).
- Differenze tra piattaforme: `Utilities/Platform.swift` (`Platform.copy`, `screenTitle`, `pushedPageTitle`, `.trailingBar`,
  `pagePadding`, `CardGrid` (anche `equalRowHeights`), `ChipRow`, `glassButton`, `PlatformNavigationStack`,
  `SplitColumns`/`StackAware`, `sheetFrame`, `localSearchable`/`LocalSearchField`,
  `InlineProgress`, `CenteredCircle`, `UnobservedValue`). Usare questi invece di `#if` sparsi o di
  API UIKit/AppKit nelle viste.
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
  della ricerca generale: campo `.searchable` sulla split view; selezionarlo o scrivere apre `SearchView` nel dettaglio,
  `nav.show(_:)` torna a una sezione chiudendo la ricerca, ⌘F la attiva), finestra `Window` singola + scena `Settings`
  (`MacSettingsView` a schede, con le stesse sezioni di `SettingsView`).
- Barra della finestra su macOS, costruita in modo standard (niente colori, misure o allineamenti personalizzati):
  titolo in New York a sinistra, pulsanti della pagina a destra, poi Aggiorna e infine la ricerca (che diventa
  un'icona da sola quando manca spazio). Come è fatta:
  - `screenTitle` mette il titolo (etichetta in New York in `.navigation`, il titolo di sistema è tolto) e Aggiorna.
    Ogni pagina della finestra principale ce l'ha, comprese quelle aperte da un'altra (per quelle che su iOS non hanno
    titolo c'è `pushedPageTitle`).
  - La barra mette prima gli elementi dei modificatori più esterni (verificato): `screenTitle` va applicato prima
    (più all'interno) del `.toolbar` della pagina, altrimenti Aggiorna finisce prima dei pulsanti della pagina.
  - Il distanziatore flessibile tra titolo e pulsanti è nel `.toolbar` della `NavigationStack` del dettaglio
    (esterno, quindi primo; resta anche nelle pagine aperte da un'altra). Togliendo il titolo di sistema SwiftUI non lo
    mette più da solo e tutto finirebbe accanto al titolo.
  - `.primaryAction` su macOS sta a sinistra: per il lato destro usare `.trailingBar` (`.automatic`).
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
  se l'app non ha un profilo di provisioning (senza capacità che lo richiedano, nemmeno con il team impostato).
  In lettura cerca sempre in entrambi: senza autorizzazione `SecItemCopyMatching` sul moderno risponde
  `errSecItemNotFound`, non `errSecMissingEntitlement` (verificato; per questo a ogni avvio si doveva rientrare).
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
  Su macOS un testo con `fixedSize(horizontal: false, vertical: true)` fuori da uno scorrimento fa calcolare
  un'altezza minima enorme (testo largo zero) e la finestra impagina tutto fuori posto: usare `lineLimit`.
  Dentro `TimetableStore.mutate` non leggere `timetable` (accesso simultaneo → crash): calcolare prima ciò che serve.
  Nella vista Giorno `contentShape` e gesti vanno prima di `.offset` (dopo valgono per la posizione di partenza);
  su iPhone il trascinamento usa `LongPressDragRecognizer` (UIKit): quelli di SwiftUI perdevano contro lo scorrimento.
  `fileImporter` chiude il selettore (e il suo `isPresented`) prima di consegnare i file: lo stato che serve dopo va
  tenuto a parte. Su macOS i file scelti dall'utente richiedono `ENABLE_USER_SELECTED_FILES = readwrite`.
- `Theme/Theme.swift`: palette (crema `#F7F2E8` / grafite `#1E1D1C`, accento `#A23E2F`), font New York anche
  nella UINavigationBar, modificatore `.card()`.
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

## Layout su macOS
- Barra laterale al posto delle schede; "Tu" diventa un riepilogo (profilo, statistiche, riquadri delle sezioni).
- Orario su iPhone: solo viste Lista e Giorno (`TimetableMode.available`; la Calendario resta su Mac e nella Dashboard).
  La settimana (`TimetableWeekHeader`) galleggia sopra gli eventi in uno `ZStack`; lo scorrimento ha
  `safeAreaPadding(.top)` pari all'altezza della settimana intera più ciò che galleggia sotto (bozza, modifica),
  costante quando si riduce, così la pagina non salta e il titolo grande si comporta come nelle altre schede.
  Nella vista Lista (`WeekHeaderScroll`) ci sono due posizioni di riposo, cima (intera) e 98 punti (ridotta, il bordo
  inferiore ha seguito gli eventi); lo scorrimento normale comincia da 98. Tra le due si scatta, non si scorre: un gesto
  dalla cima arriva al massimo a 98 (anche con l'inerzia); un gesto o l'inerzia da più in basso si ferma a 98 con la
  resistenza di un bordo e la settimana resta ridotta; solo un gesto che parte da fermi a 98 apre la settimana tirando
  (a metà velocità); lasciando il dito si va alla posizione più vicina, mai a metà. Il tipo di gesto si decide all'inizio
  del pan (`WeekHeaderScroll.Gesture`); `WeekHeaderScrollControl` limita e rallenta il `contentOffset` dello
  `UIScrollView` mentre si trascina (va nello sfondo del contenuto, dentro lo scorrimento) e `WeekHeaderSnap` sceglie
  dove fermarsi (le coordinate di `ScrollTarget` sono già senza il margine: 0 = cima, verificato). Il contenuto è alto
  almeno quanto la vista più 98, così la settimana si riduce anche nei giorni corti. L'avanzamento si legge solo in
  `WeekHeaderHost` (cambia a ogni fotogramma). Vibra arrivando intera o ridotta; toccata da ridotta si riapre finché
  non si scorre di 20 punti.
  Nella vista Giorno si riduce a una striscia di numeri seguendo la barra delle schede (`FloatingHeaderCollapse`): `UITabBar._isMinimized`
  non si può usare ("This can only be called by an approved app", l'app si chiude), quindi si guarda quale dei due
  `_UITabBarPlatterView` è visibile (il ridotto è il più stretto); se la struttura cambia vale una regola di riserva
  misurata (riduce oltre 140 punti dalla cima, riapre in cima e tirando in fondo con il dito, non scorrendo in su).
  `ScrollGeometry.containerSize` è già senza i margini (verificato). Il passaggio è una vista `Animatable`
  (`progress` 0–1) che interpola posizioni, rettangolo → cerchio e dissolvenze; si controlla registrando il simulatore.
- Impostazioni su iPhone: elenco di sottopagine (Generale, Voti, Dashboard, Orario, Notifiche, Account) con le stesse
  sezioni delle schede della finestra Impostazioni del Mac.
- Verifiche nascoste (menu dell'orario, `TimetableHiddenTestsView`): nascoste a mano (`hiddenTests`) o da regole
  (`Timetable.testRules`, `TestHidingRules`: docenti, materie, giorni, periodi, parole, senza lezione in orario);
  mostrandone a mano una nascosta da una regola finisce in `shownTests` (eccezione), nascondendola di nuovo l'eccezione
  si toglie. Il motivo viene da `TimetableStore.hiddenReason(for:unmatched:)`; la Dashboard non ne è toccata.
- Orario, barra: niente frecce per cambiare giorno; "Oggi" compare solo se il giorno scelto non è oggi (⌘T su Mac),
  come "Domani" nella Dashboard.
- Orario su Mac: Lista e Calendario con `SplitColumns` (settimana o mese + riepilogo della settimana | giorno); la
  vista Giorno (`MacWeekTimeline`) mostra tutta la settimana con gli eventi trascinabili anche tra i giorni.
  Fuori da uno scorrimento `WeekStrip` va con `.fixedSize(horizontal: false, vertical: true)`, altrimenti si allunga.
- Barra della finestra: di serie macOS le dà sempre lo sfondo con la riga, anche con la pagina in cima (verificato
  anche con un'app SwiftUI minima: le `NSScrollPocket` restano spente). `MacRootView` la tiene trasparente
  (`toolbarBackgroundVisibility(.hidden)`) e la mostra (chiara e sfocata) solo quando uno scorrimento della pagina che
  arriva sotto la barra non è in cima (`WindowBarScrollObserver`, che ascolta i cambi dei limiti delle `NSClipView`).
  Nella schermata di accesso la barra c'è ma senza sfondo: toglierla del tutto cambierebbe pulsanti e angoli.
- Ricerca su Mac: un clic su un'area vuota della pagina di ricerca toglie la selezione al campo (sfondo con
  `onTapGesture` sotto i risultati, che lo coprono; il contenuto riempie almeno l'altezza visibile).
- `Form` su Mac: più controlli in una riga (es. `DatePicker` + `Stepper`) finiscono uno sopra l'altro e tagliati, e un
  `Stepper` con un `LabeledContent` come etichetta stacca il valore dalle frecce: usare `LabeledContent` con i
  controlli in un `HStack` (`labelsHidden`) e `LabeledStepper`. Nel generatore gli intervalli si tolgono con il
  pulsante rosso (su iPhone scorrendo).
- Pagine a due colonne con `SplitColumns` (laterale fissa + principale, scorrimento separato; sotto ~780 pt si
  impilano): Dashboard (calendario + prossimi giorni | giorno, con lezioni in colonna a parte da 580 pt), Voti,
  dettaglio materia, Scrutini, Anni precedenti, Lezioni. Bacheca: elenco + dettaglio affiancati sopra 820 pt.
- Elenchi di card in `CardGrid` (una colonna su iOS, griglia adattiva su Mac); filtri in `ChipRow` (a capo su Mac).
- Dashboard su Mac: il giorno scelto è il titolo nella barra, come nelle altre sezioni; a destra "Domani" (solo se il
  giorno scelto non è domani, ⇧⌘T) e il menu della vista (con "Vai a oggi"), poi Aggiorna e la ricerca.
  "Nei prossimi giorni" cambia identità (`upcomingGeneration`) in `select(_:)`, insieme al giorno: su iOS sempre, su
  macOS solo se la sezione è espansa e il contenuto cambia davvero. L'identità non deve dipendere dallo stato
  compresso: comprimere sostituirebbe la sezione intera e l'intestazione scenderebbe e risalirebbe. La transizione
  usa lo spostamento del giorno scelto (`upcomingTransition`, `dayDetailHeight`): `.move(edge:)` sposta di tutta
  l'altezza della vista, troppo con la lista aperta e troppo poco con la sola intestazione.
- La schermata di accesso ha un elemento invisibile nella barra: senza barra i pulsanti a semaforo si spostano.
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
- Ridimensionando la finestra: niente `@State` con la larghezza (`onGeometryChange` di un `CGFloat`), che ricalcola la
  pagina a ogni fotogramma; misurare solo il passaggio (`Bool`, con un po' di isteresi in `SplitColumns`). Il passaggio
  da due colonne a una ricostruisce le due strutture (50–130 ms, quasi tutto in SwiftUI); tenere la colonna principale
  nello stesso scorrimento è risultato molto più lento (~400 ms).
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
