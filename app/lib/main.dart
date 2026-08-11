import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n/gen/app_localizations.dart';

import 'account/user_profile.dart';
import 'add_book/add_book_page.dart';
import 'add_book/scan_page.dart';
import 'app_drawer.dart';
import 'book_detail/book_detail_page.dart';
import 'data/database.dart';
import 'data/local_text_index.dart';
import 'data/library_queries.dart';
import 'data/backup_schedule.dart';
import 'data/library_repository.dart';
import 'import/filename_metadata.dart';
import 'import/folder_import_page.dart';
import 'import/folder_import_service.dart';
import 'import/import_plan.dart';
import 'import/incoming_share.dart';
import 'navigation_history.dart';
import 'onboarding/first_run_sheet.dart';
import 'physical/physical_libraries_page.dart';
import 'server/auto_pusher.dart';
import 'server/background_sync.dart';
import 'server/connection_store.dart';
import 'server/continue_widget.dart';
import 'server/live_sync.dart';
import 'server/server_client.dart';
import 'server/server_page.dart';
import 'server/sync_service.dart';
import 'settings/app_settings.dart';
import 'settings/appearance.dart';
import 'settings/book_face.dart';
import 'settings/preferences_page.dart';
import 'settings/shelf_sort.dart';
import 'settings/wallpaper.dart';
import 'shelf/shelf_target_sheet.dart';
import 'shelf/book_list_view.dart';
import 'shelf/command_palette.dart';
import 'shelf/content_search.dart';
import 'shelf/library_header.dart';
import 'shelf/shelf_view.dart';
import 'shortcuts.dart';
import 'snack_bars.dart';
import 'wishlist/wishlist_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status/nav bars. Android 15 (targetSdk 35) enforces this
  // anyway; setting it explicitly makes earlier Android versions match. The
  // Material scaffolding (AppBar, NavigationBar, FAB, bottom sheets) already
  // insets itself; custom bottom bars use SafeArea (see the EPUB reader).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // A phone's image budget. Flutter's default is 100 MB of *decoded* images,
  // which a shelf of covers reaches easily — a library of 88 books was
  // measured holding 300 MB of graphics memory and a 900 MB resident set on
  // Android before anything else asked for memory. The reader then wants
  // page bitmaps from PDFium on top of that, and a phone that cannot allocate
  // them renders nothing rather than complaining.
  //
  // Desktops keep the default: there the covers are the point of the window
  // and the memory is there.
  if (Platform.isAndroid || Platform.isIOS) {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20; // 48 MB
    PaintingBinding.instance.imageCache.maximumSize = 200;
  }
  final repository = await LibraryRepository.open(VellumDatabase());
  final profile = await UserProfileStore.load(dataDir: repository.dataDir);
  final settings = await AppSettingsStore.load();
  final connection = await ServerConnection.load();
  // The background-sync schedule (plan 5 #40). Re-applied on every launch so a
  // changed interval takes effect without leaving the old registration behind;
  // a no-op off Android and when the setting is off.
  unawaited(applySchedule(policyFrom(
    settings,
    hasServer: connection.isConnected,
  )));

  // Unattended backup (plan 5 #13). Deliberately *not* awaited: a backup of a
  // large library takes a while, and blocking the first frame on it would make
  // the app look broken once a day. It also never throws — see `runIfDue`.
  unawaited(BackupScheduler(repository: repository, settings: settings)
      .runIfDue());
  // Expire the trash (plan 5 #52). Not awaited, for the same reason as the
  // backup above: the books involved are already invisible, so nothing on the
  // first frame depends on the sweep having run. It swallows its own errors —
  // a file the OS won't release just waits for the next launch.
  unawaited(repository.trash.sweep());
  // Index a few books' text, if the user asked for local content search.
  // Not awaited, and bounded per launch rather than draining the queue: the
  // first pass over a large library is minutes of extraction, and the shelf
  // must not wait on it. A killed app resumes from the same queue next time.
  if (settings.indexBookText && textIndexSupportedHere) {
    unawaited(() async {
      final index = LocalTextIndex(repository.db, dataDir: repository.dataDir);
      await index.enqueueMissing();
      await index.processPending(limit: 8);
    }()
        .catchError((_) {}));
  }
  runApp(VellumApp(
    repository: repository,
    profile: profile,
    settings: settings,
    connection: connection,
  ));
}

class VellumApp extends StatelessWidget {
  VellumApp({
    super.key,
    required this.repository,
    required this.profile,
    required this.settings,
    required this.connection,
  });

  final LibraryRepository repository;
  final UserProfileStore profile;
  final AppSettingsStore settings;
  final ServerConnection connection;

  /// Back/forward for the mouse's side buttons. Owned here because it is both a
  /// navigator observer and something the shell reports its tab changes to.
  final NavigationHistory _history = NavigationHistory();

  @override
  Widget build(BuildContext context) {
    // The whole app is rebuilt on an appearance change, which is the point:
    // seed, mode and material are meant to move everything at once, not just
    // the screen you happen to be on (plan 5 #39). DynamicColorBuilder hands
    // back nulls off Android, so the seed path is what runs everywhere else.
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          final themes = vellumThemes(
            seed: settings.seedColor,
            dynamicLight: lightDynamic,
            dynamicDark: darkDynamic,
            useDynamic: settings.useDynamicColor,
          );
          return MaterialApp(
            title: 'Vellum', // i18n-ignore: a proper noun, never translated
            // Localization scaffolding (plan 5 #38). English only for now; the
            // point is that every string added from here on has somewhere to
            // go, and that plurals are ICU rather than `n == 1 ? '' : 's'`.
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: themes.light,
            darkTheme: themes.dark,
            themeMode: settings.themeMode,
            navigatorObservers: [_history],
            // Inside the app, so `Navigator.of` here is the one being driven,
            // and above every route, so the buttons work on any screen.
            builder: (context, child) => MouseNavigation(
              history: _history,
              child: child ?? const SizedBox.shrink(),
            ),
            home: LibraryPage(
              repository: repository,
              profile: profile,
              settings: settings,
              connection: connection,
              history: _history,
            ),
          );
        },
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.repository,
    required this.profile,
    required this.settings,
    required this.connection,
    this.history,
  });

  final LibraryRepository repository;
  final UserProfileStore profile;
  final AppSettingsStore settings;
  final ServerConnection connection;

  /// Told about tab changes so the mouse's back button can undo one. Optional
  /// so tests can pump the shell without one.
  final NavigationHistory? history;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _query = '';

  /// Whether the search is looking inside book contents (plan 5 #32) rather
  /// than at titles and authors. Only reachable when the server advertises
  /// `content_search`; reset whenever the query is cleared, so a disconnect
  /// can't strand the shelf on a tab that can't answer.
  bool _searchInsideBooks = false;
  // The active genre facet, or null for "all genres". Kept separate from the
  // text query so a genre filter and a text search can be on at once, and so it
  // can be shown/cleared as a chip rather than hidden in the search box.
  String? _genreFilter;
  // The reading-status facet (plan 5 #18), or null for "any status".
  ReadingStatus? _statusFilter;
  int _tab = 0; // 0 = digital shelf, 1 = physical libraries

  /// Book ids ticked in selection mode (next features #4). Empty means the mode
  /// is off — there is no separate flag, because a selection of nothing has
  /// nothing to act on and an app bar counting to zero is just in the way.
  final Set<String> _selection = {};
  // The continue-reading / recently-added strip (plan 5 #25), hidden for this
  // session only: its value is reappearing when you come back mid-book, not
  // being a preference to manage.
  bool _headerDismissed = false;
  Timer? _searchDebounce;
  final _searchController = TextEditingController();

  /// Focus for the app-bar search box, so Ctrl+F can put the cursor in it
  /// (plan 5 #26).
  final _searchFocus = FocusNode();

  // One sync service for the whole app (launch auto-sync + the server page),
  // so its re-entrancy guard spans every way a sync can start.
  late final SyncService _sync =
      SyncService(widget.repository, profile: widget.profile);

  // Debounced background push of dirty books while connected, so a long editing
  // session keeps the server/console fresh without waiting for the next launch.
  late final AutoPusher _autoPusher = AutoPusher(
    repository: widget.repository,
    sync: _sync,
    client: () => widget.connection.client,
    enabled: () => widget.settings.autoPush,
  );

  /// Live change hints from the server (plan 5 #8). Only ever *triggers* the
  /// existing delta pull, so there is no second conflict model — and it stays
  /// silent when the server is old, unreachable, or simply not there.
  late final LiveSyncTrigger _live = LiveSyncTrigger(
    client: () => widget.connection.client,
    isConnected: () =>
        widget.connection.isConnected &&
        (widget.connection.capabilities?.hasFeature('live_events') ?? false),
    onHint: _pullFromHint,
  );

  /// Books opened or shared into Vellum from another app (plan 5 #20).
  late final IncomingShare _incoming = IncomingShare();
  StreamSubscription<List<String>>? _incomingSub;
  StreamSubscription<LauncherShortcut>? _shortcutSub;

  LibraryRepository get repository => widget.repository;

  /// Switches section, remembering where we were so the mouse's back button can
  /// undo it. Every tab change goes through here — one that didn't would leave
  /// a hole in the history that back silently skips over.
  void _goToTab(int tab) {
    if (tab == _tab) return;
    widget.history?.recordSection(_tab);
    setState(() => _tab = tab);
  }

  @override
  void initState() {
    super.initState();
    // `PopScope.canPop` reads `_searchFocus.hasFocus`, and a focus change is
    // not a rebuild — without this the flag is whatever it was when the frame
    // was built, and Back would leave the page anyway.
    _searchFocus.addListener(_onSearchFocusChanged);
    final history = widget.history;
    if (history != null) {
      history.applySection = (section) => setState(() => _tab = section);
      history.currentSection = () => _tab;
    }
    _autoSync();
    _autoPusher.start();
    _live.start();
    _offerWatchedFolder();
    _listenForSharedBooks();
    _showFirstRun();
    // Catch up covers that predate dominant-colour extraction (no-op once done).
    widget.repository.backfillCoverColors();
    // Refresh the home-screen widget (plan 5 #40) — a no-op off Android, and
    // silent everywhere. Pushed at launch and after a sync, which is when the
    // answer can actually have changed.
    unawaited(updateContinueWidget(widget.repository));
  }

  /// Records that a sync happened, so the background schedule's "is it due?"
  /// has something to measure from — including when the user synced by hand.
  Future<void> _noteBackgroundSyncRan() async {
    final policy = policyFrom(
      widget.settings,
      hasServer: widget.connection.isConnected,
    );
    if (policy.interval == BackgroundSyncInterval.off) return;
    await widget.settings.setLastBackgroundSyncAt(DateTime.now());
  }

  /// A delta pull provoked by a live hint (plan 5 #8).
  ///
  /// Quiet on purpose — no snackbar. The user didn't ask for this sync, and a
  /// toast every time someone edits a book in the console would be noise; the
  /// shelf's streams update on their own once the rows land.
  Future<void> _pullFromHint() async {
    final client = widget.connection.client;
    if (client == null || _sync.isRunning) return;
    try {
      await _sync.pull(
        client,
        cursor: widget.connection.syncCursor,
        onCursor: widget.connection.setSyncCursor,
      );
    } catch (_) {
      // Offline or racing another sync — the next launch or manual sync covers
      // it, exactly as before this feature existed.
    }
  }

  /// Best-effort sync on launch when a server is connected. Quiet by design:
  /// the app is local-first, so an unreachable server is normal — only a
  /// result worth knowing about (changes or issues) surfaces a snackbar.
  Future<void> _autoSync() async {
    final conn = widget.connection;
    final client = conn.client;
    if (client == null) return;
    // Background sync (plan 5 #40) shares this path rather than duplicating it:
    // "sync when the app comes up and enough time has passed" is the same work
    // as the launch sync, and a second implementation would be a second set of
    // cursor bugs. WorkManager only decides *when*; the policy decides whether.
    unawaited(_noteBackgroundSyncRan());
    try {
      final report = await _sync.sync(
        client,
        cursor: conn.syncCursor,
        onCursor: conn.setSyncCursor,
        scope: widget.settings.syncScope,
      );
      // Reading position rides its own pass, after the sync guard is free and
      // only when the user opted in (plan 5 #5). Its own try/catch: a failure
      // here must not make a successful library sync look failed.
      await _syncReadingPosition(client);
      unawaited(updateContinueWidget(repository));
      if (!mounted) return;
      final changed = report.pulled +
          report.pushed +
          report.deletedLocally +
          report.deletedRemotely;
      if (changed == 0 && !report.hasIssues) return;
      final l10n = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // ICU both ways (plan 5 #38): gluing a hand-built plural onto a
            // localized sentence with a ternary is the same bug in a better
            // disguise, and it is the exact pattern this item exists to remove.
            report.hasIssues
                ? l10n.syncResultWithIssues(
                    report.pulled,
                    report.pushed,
                    l10n.syncIssues(report.issues.length),
                  )
                : l10n.syncResult(report.pulled, report.pushed),
          ),
        ),
      );
    } on ServerException catch (e) {
      // A dead session drops the token so the server page shows sign-in.
      if (e.isUnauthorized) await conn.clearExpiredSession();
    } catch (_) {
      // Offline or unreachable — stay quiet, the local library works as is.
    }
  }

  /// Publishes this device's reading position and caches the other devices'
  /// (plan 5 #5). No-op unless the user turned the option on; silent on failure
  /// like the rest of the launch sync, since nothing local depends on it.
  Future<void> _syncReadingPosition(VellumServerClient client) async {
    if (!widget.settings.syncReadingPosition) return;
    final conn = widget.connection;
    try {
      await _sync.syncReadingProgress(
        client,
        deviceId: widget.settings.deviceId,
        deviceLabel: widget.settings.deviceLabel,
        cursor: conn.readingCursor,
        onCursor: conn.setReadingCursor,
      );
    } catch (_) {
      // Offline, or a server without the endpoint — the position simply stays
      // local until next time.
    }
  }

  /// Offers to import from the watched folder if it holds books this library
  /// doesn't (plan 5 #15).
  ///
  /// Launch-only and *offered*, never automatic: a folder can hold files the
  /// user deliberately didn't import, and silently adding books to someone's
  /// library because a download finished would be the wrong kind of helpful. The
  /// scan itself is the wizard's normal dry run, so the count here is a cheap
  /// hash-free pre-check — anything else waits for the user to say yes.
  Future<void> _offerWatchedFolder() async {
    final folder = widget.settings.watchedImportFolder;
    if (folder == null) return;
    final directory = Directory(folder);
    if (!await directory.exists()) return; // unplugged drive, moved folder
    final service = FolderImportService(repository);
    final List<File> found;
    try {
      found = await service.findImportableFiles(directory);
    } catch (_) {
      return; // unreadable folder — not worth a message
    }
    if (found.isEmpty || !mounted) return;
    // Cheap pre-check so a folder whose books are all imported doesn't nag on
    // every launch. Compared by *guessed title*, not by path: a stored file is
    // named after its uuid, so the original file name is no longer on disk to
    // compare with. Being approximate is fine in this direction — the worst case
    // is one extra prompt, and the dry run that follows compares by hash.
    final known = {
      for (final book in await repository.db.select(repository.db.books).get())
        normalizeForMatch(book.title),
    };
    final unseen = found.where((f) {
      final guess = parseFilename(filenameStem(f.path)).title;
      return guess == null || !known.contains(normalizeForMatch(guess));
    }).length;
    if (unseen == 0 || !mounted) return;

    final l10n = L10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar(
        duration: const Duration(seconds: 8),
        // ICU, not `'$n file${n == 1 ? '' : 's'}'` — the hand-built plural this
        // item exists to remove (plan 5 #38). No other language survives it.
        content: Text(l10n.newFilesInWatchedFolder(unseen)),
        action: SnackBarAction(
          label: l10n.review,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FolderImportPage(
                repository: repository,
                settings: widget.settings,
                initialFolder: folder,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Handles books arriving from another app's "open with" / share sheet.
  ///
  /// Both arrival shapes are handled here, because they are equally normal: the
  /// share may *be* what launched the app (the paths are waiting), or it may
  /// arrive while Vellum is already open (the stream). One file goes to the
  /// add-book form pre-filled, several to the import plan (#15) — the same
  /// review either way, since the alternative is silently adding books someone
  /// only meant to look at.
  void _listenForSharedBooks() {
    _incomingSub = _incoming.files.listen(_openSharedFiles);
    _incoming.takeInitialFiles().then((paths) {
      if (paths.isNotEmpty) _openSharedFiles(paths);
    });
    // Launcher shortcuts (plan 5 #40), on the same channel: both answer "what
    // did the user tap to get here?".
    _shortcutSub = _incoming.shortcuts.listen(_runShortcut);
    _incoming.takeInitialShortcut().then((shortcut) {
      if (shortcut != null) _runShortcut(shortcut);
    });
  }

  /// A launcher shortcut lands on the same destination the in-app action does,
  /// rather than a parallel entry point with its own state to get wrong.
  void _runShortcut(LauncherShortcut shortcut) {
    if (!mounted) return;
    switch (shortcut) {
      case LauncherShortcut.scan:
        _openScan(context);
      case LauncherShortcut.add:
        _openAddBook(context);
      case LauncherShortcut.continueReading:
        // Whatever the shelf's own "continue reading" strip would open. Nothing
        // to continue is not an error — it opens the shelf, which is where you
        // would have started anyway.
        _openMostRecentlyRead();
    }
  }

  Future<void> _openMostRecentlyRead() async {
    final view = await repository.queries
        .watchLibrary(shelfId: null, query: '', sort: widget.settings.shelfSort)
        .first;
    final continuing = LibraryHighlights.from(view).continueReading;
    if (!mounted || continuing.isEmpty) return;
    _openBook(continuing.first);
  }

  Future<void> _openSharedFiles(List<String> paths) async {
    if (!mounted || paths.isEmpty) return;
    final navigator = Navigator.of(context);
    if (paths.length == 1) {
      final added = await navigator.push<String>(MaterialPageRoute(
        builder: (_) => AddBookPage(
          repository: repository,
          settings: widget.settings,
          initialFilePath: paths.single,
        ),
      ));
      if (added != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).bookAdded(added))),
        );
      }
      return;
    }
    await navigator.push(MaterialPageRoute(
      builder: (_) => FolderImportPage(
        repository: repository,
        settings: widget.settings,
        initialFiles: paths,
      ),
    ));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _autoPusher.dispose();
    _live.dispose();
    _incomingSub?.cancel();
    _shortcutSub?.cancel();
    _incoming.dispose();
    super.dispose();
  }

  // Re-packing the shelf rows on every keystroke is expensive; wait for a
  // short pause in typing before filtering.
  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _query = value;
          // Clearing the box leaves the content tab behind, so the shelf is
          // never stranded on a tab with nothing to show.
          if (value.trim().isEmpty) _searchInsideBooks = false;
        });
      }
    });
  }

  Future<void> _openAddBook(BuildContext context) async {
    final addedTitle = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            AddBookPage(repository: repository, settings: widget.settings),
      ),
    );
    if (addedTitle != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).bookAdded(addedTitle))),
      );
    }
  }

  Future<void> _openScan(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanPage(repository: repository)),
    );
  }

  /// The first-run introduction (plan 5 #41), on the first launch only. It
  /// reports a choice rather than navigating itself, so the routes all stay here
  /// where the rest of the shelf's navigation lives.
  Future<void> _showFirstRun() async {
    // After the frame, so the sheet has a Scaffold to sit in.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final action = await FirstRunSheet.maybeShow(context, widget.settings);
    if (action == null || !mounted) return;
    switch (action) {
      case FirstRunAction.importFolder:
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FolderImportPage(
            repository: repository,
            settings: widget.settings,
          ),
        ));
      case FirstRunAction.scan:
        if (mounted) await _openScan(context);
      case FirstRunAction.addOne:
        if (mounted) await _openAddBook(context);
      case FirstRunAction.connectServer:
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ServerPage(
            connection: widget.connection,
            repository: repository,
            sync: _sync,
            settings: widget.settings,
          ),
        ));
      case FirstRunAction.createRoom:
        if (!mounted) return;
        _goToTab(1);
        await promptCreateLibrary(context, repository, widget.settings);
    }
  }

  /// Opens a book's detail page — the same destination a spine tap reaches, so
  /// the header strip and the shelf can't drift apart.
  void _openBook(Book book) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookDetailPage(
        book: book,
        repository: repository,
        settings: widget.settings,
        connection: widget.connection,
        onGenreTap: _applyGenreFilter,
      ),
    ));
  }

  /// Applies the genre facet from a tapped genre chip on a book's detail page.
  /// Whether this server can search inside book contents (plan 5 #32). Reads
  /// the capability handshake rather than probing: a tab that 400s on every
  /// keystroke is worse than no tab.
  bool get _contentSearchAvailable =>
      _localTextIndex != null ||
      (widget.connection.isConnected &&
          (widget.connection.capabilities?.hasFeature('content_search') ??
              false));

  /// The on-device content index, or null when it can't or shouldn't be used —
  /// off Android, and off unless the setting is on. Built per read rather than
  /// held: it is a thin wrapper over the database with no state of its own
  /// beyond the extraction guard, so a stale one cannot linger after the
  /// setting is switched off.
  LocalTextIndex? get _localTextIndex =>
      widget.settings.indexBookText && textIndexSupportedHere
          ? LocalTextIndex(repository.db, dataDir: repository.dataDir)
          : null;

  /// Sets the dedicated filter (shown as a removable chip near the search)
  /// rather than the search box, so any text search you had stays put.
  void _applyGenreFilter(String genre) {
    setState(() => _genreFilter = genre);
  }

  // ---- Keyboard shortcuts and the command palette (plan 5 #26) ------------

  /// Everything the shelf can do, in one list: the key bindings, the palette,
  /// and the tooltips all read from here, so an action can't be reachable one
  /// way and invisible the others.
  /// Everything the shelf can do, localized (plan 5 #38): the palette searches
  /// these by name, so they have to be in the reader's language or the search
  /// box is useless to them.
  List<LibraryCommand> _commands() {
    final l10n = L10n.of(context);
    return [
        LibraryCommand(
          id: 'search',
          label: l10n.cmdSearch,
          icon: Icons.search,
          key: LogicalKeyboardKey.keyF,
          run: () {
            _goToTab(0);
            _searchFocus.requestFocus();
            _searchController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchController.text.length,
            );
          },
        ),
        LibraryCommand(
          id: 'add',
          label: l10n.addABook,
          icon: Icons.add,
          key: LogicalKeyboardKey.keyN,
          run: () => _openAddBook(context),
        ),
        LibraryCommand(
          id: 'import',
          label: l10n.cmdImportFolder,
          icon: Icons.folder_open,
          key: LogicalKeyboardKey.keyI,
          run: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FolderImportPage(
              repository: repository,
              settings: widget.settings,
            ),
          )),
        ),
        LibraryCommand(
          id: 'scan',
          label: l10n.scanBarcode,
          icon: Icons.barcode_reader,
          run: () => _openScan(context),
        ),
        LibraryCommand(
          id: 'wishlist',
          label: l10n.cmdWishlist,
          icon: Icons.bookmark_border,
          run: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WishlistPage(
              repository: repository,
              settings: widget.settings,
              connection: widget.connection,
            ),
          )),
        ),
        LibraryCommand(
          id: 'wish-add',
          label: l10n.cmdAddWish,
          icon: Icons.bookmark_add_outlined,
          run: () => promptAddToWishlist(context, repository),
        ),
        LibraryCommand(
          id: 'face',
          label: l10n.cmdToggleFace,
          icon: Icons.flip_to_front,
          key: LogicalKeyboardKey.keyB,
          // Cycles rather than flips: there are three views now, and a
          // shortcut that could only reach two of them would leave the list
          // only settable from Preferences.
          run: () => widget.settings.setBookFace(
            BookFace.values[
                (widget.settings.bookFace.index + 1) % BookFace.values.length],
          ),
        ),
        LibraryCommand(
          id: 'sync',
          label: l10n.cmdSync,
          icon: Icons.cloud_sync_outlined,
          key: LogicalKeyboardKey.f5,
          run: _syncNow,
        ),
        LibraryCommand(
          id: 'preferences',
          label: l10n.cmdPreferences,
          icon: Icons.tune,
          key: LogicalKeyboardKey.comma,
          run: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PreferencesPage(
              settings: widget.settings,
              repository: repository,
              connection: widget.connection,
              sync: _sync,
            ),
          )),
        ),
        LibraryCommand(
          id: 'physical',
          label: l10n.physicalLibraries,
          icon: Icons.grid_view_rounded,
          run: () => _goToTab(1),
        ),
        // Not in the palette: opening the palette from inside it is a no-op,
        // and Escape is a contextual key rather than a command anyone hunts
        // for by name.
        LibraryCommand(
          id: 'palette',
          label: l10n.cmdShowCommands,
          icon: Icons.keyboard_command_key,
          key: LogicalKeyboardKey.keyK,
          inPalette: false,
          run: _openCommandPalette,
        ),
        LibraryCommand(
          id: 'clear',
          label: l10n.clearSearchAndFilters,
          icon: Icons.filter_alt_off_outlined,
          key: LogicalKeyboardKey.escape,
          inPalette: false,
          run: _escape,
        ),
    ];
  }

  /// The contextual app bar shown while books are ticked (next features #4).
  ///
  /// Replaces the search bar rather than sitting under it: the actions here all
  /// operate on the selection, and leaving the search visible would invite a
  /// filter change that silently alters what "the selection" means.
  PreferredSizeWidget _selectionBar() {
    final l10n = L10n.of(context);
    final count = _selection.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
        onPressed: () => setState(_selection.clear),
      ),
      title: Text(l10n.selectionCount(count)),
      actions: [
        IconButton(
          icon: const Icon(Icons.playlist_add),
          tooltip: l10n.putOnShelf,
          onPressed: _moveSelectionToShelf,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.moveToTrash,
          onPressed: _trashSelection,
        ),
      ],
    );
  }

  /// The books currently ticked, in shelf order.
  Future<List<Book>> _selectedBooks() async {
    final all = await repository.watchAllBooks().first;
    return [
      for (final b in all)
        if (_selection.contains(b.id)) b,
    ];
  }

  Future<void> _trashSelection() async {
    final ids = _selection.toList();
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    for (final id in ids) {
      await repository.trashBook(id);
    }
    if (!mounted) return;
    setState(_selection.clear);
    messenger.showSnackBar(appSnackBar(
      content: Text(l10n.trashedBooks(ids.length)),
      action: SnackBarAction(
        label: l10n.undo,
        onPressed: () async {
          for (final id in ids) {
            await repository.trash.restore(id);
          }
        },
      ),
    ));
  }

  /// Puts the selection on a shelf. The sheet asks *which* shelf and *what to
  /// do* — Move or Add — rather than guessing: "move" is only well defined when
  /// you are looking at a shelf, and from the whole library there is nothing to
  /// leave. Decided in next features #4.
  Future<void> _moveSelectionToShelf() async {
    final l10n = L10n.of(context);
    final fromShelfId = widget.settings.selectedShelfId;
    final shelves = await repository.watchShelves().first;
    if (!mounted) return;
    if (shelves.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
        content: Text(l10n.noShelvesYet),
      ));
      return;
    }
    final books = await _selectedBooks();
    if (!mounted) return;

    final choice = await showModalBottomSheet<({Shelf shelf, bool move})>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ShelfTargetSheet(
        shelves: shelves,
        count: books.length,
        // Move is only offered when there is a shelf to leave, and is the
        // default there because that is what was asked for.
        canMove: fromShelfId != null,
      ),
    );
    if (choice == null || !mounted) return;

    for (final book in books) {
      if (choice.move && fromShelfId != null && fromShelfId != choice.shelf.id) {
        await repository.removeFromShelf(book.id, fromShelfId);
      }
      await repository.addToShelf(book.id, choice.shelf.id);
    }
    if (!mounted) return;
    setState(_selection.clear);
    ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
      content: Text(choice.move
          ? l10n.movedToShelf(books.length, choice.shelf.name)
          : l10n.addedToShelf(books.length, choice.shelf.name)),
    ));
  }

  /// Escape and the system Back gesture: leave selection mode first, and only
  /// clear the search once nothing is ticked. Otherwise one key does two
  /// unrelated things at once and you lose a selection you were building.
  void _escape() {
    if (_selection.isNotEmpty) {
      setState(_selection.clear);
      return;
    }
    _clearSearchAndFilters();
  }

  void _toggleSelected(Book book) => setState(() {
        if (!_selection.remove(book.id)) _selection.add(book.id);
      });

  void _clearSearchAndFilters() {
    _searchFocus.unfocus();
    setState(() {
      _query = '';
      _genreFilter = null;
      _statusFilter = null;
      _searchInsideBooks = false;
    });
  }

  /// A sync the user asked for, so unlike the launch sync it reports what
  /// happened either way — including "no server connected", which is otherwise
  /// indistinguishable from a key that did nothing.
  Future<void> _syncNow() async {
    final messenger = ScaffoldMessenger.of(context);
    // Read before the first await: a BuildContext is not safe to touch after
    // one, and the lookup is a synchronous inherited-widget read.
    final l10n = L10n.of(context);
    final conn = widget.connection;
    final client = conn.client;
    if (client == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.noServerConnected)),
      );
      return;
    }
    try {
      final report = await _sync.sync(
        client,
        cursor: conn.syncCursor,
        onCursor: conn.setSyncCursor,
        scope: widget.settings.syncScope,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.syncResult(report.pulled, report.pushed)),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.syncFailed('$e'))));
    }
  }

  void _openCommandPalette() {
    showDialog<void>(
      context: context,
      builder: (_) => CommandPalette(
        commands: _commands(),
        books: repository.watchAllBooks(),
        onOpenBook: _openBook,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // CallbackShortcuts rather than a Shortcuts/Actions pair: the commands are
    // already a list of callbacks, and an Intent+Action class per binding would
    // be ceremony around nothing.
    //
    // The Focus goes *inside*, not outside: a key event walks up from whatever
    // is focused, so CallbackShortcuts only sees it if it is an ancestor of the
    // focused node. That nesting is also why a focused search box doesn't
    // swallow these — it gets the event first and passes on the keys it has no
    // use for, which is all of Ctrl+F/N/I/K/B, F5 and Escape.
    return CallbackShortcuts(
      bindings: shortcutsFor(_commands()),
      child: Focus(
        autofocus: true,
        // Android's Back unwinds what is on top of the shelf before leaving
        // it: a selection first, then the keyboard. Both are the only way out
        // on a phone, where there is no Escape key.
        //
        // The keyboard rung is the one that bites: searching the library fills
        // the screen with a keyboard you want gone to see more books, and Back
        // is what everyone reaches for. Without this it left the page instead
        // — losing the search along with it.
        child: PopScope(
          canPop: _selection.isEmpty && !_searchFocus.hasFocus,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_selection.isNotEmpty) {
              setState(_selection.clear);
              return;
            }
            // Keeps the query — only the keyboard goes.
            _searchFocus.unfocus();
          },
          child: _scaffold(context),
        ),
      ),
    );
  }

  /// Rebuilds so `PopScope` sees the current focus. Guarded on `mounted`
  /// because unfocusing during a pop can fire this after the state is gone.
  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  Widget _scaffold(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      drawer: AppDrawer(
        profile: widget.profile,
        settings: widget.settings,
        connection: widget.connection,
        repository: widget.repository,
        sync: _sync,
      ),
      appBar: _tab == 0 && _selection.isNotEmpty
          ? _selectionBar()
          : _tab == 0
          ? AppBar(
              title: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: l10n.searchHint,
                  icon: const Icon(Icons.search),
                  border: InputBorder.none,
                ),
              ),
              actions: [
                _paletteButton(),
                _statusMenu(),
                _genreMenu(),
                _sortMenu(),
              ],
            )
          : AppBar(title: Text(l10n.physicalLibraries)),
      body: IndexedStack(
        index: _tab,
        children: [
          _shelfTab(context),
          PhysicalLibrariesTab(
            repository: repository,
            settings: widget.settings,
            connection: widget.connection,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _goToTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l10n.shelfTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: l10n.physicalTab,
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          // Scan sits above Add book rather than replacing it: scanning is the
          // fast path for physical books you're holding, not a substitute for
          // the search/create form. Shown on desktop too — there it's the same
          // flow driven by a typed ISBN (plan 5 #16).
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'scan',
                  tooltip: l10n.scanBarcode,
                  onPressed: () => _openScan(context),
                  child: const Icon(Icons.barcode_reader),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'add',
                  onPressed: () => _openAddBook(context),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addBook),
                ),
              ],
            )
          : FloatingActionButton.extended(
              onPressed: () =>
                  promptCreateLibrary(context, repository, widget.settings),
              icon: const Icon(Icons.add),
              label: Text(l10n.newLibrary),
            ),
    );
  }

  /// The palette's own affordance. Without it the whole shortcut set is
  /// invisible to anyone who never tries Ctrl+K — which is most people.
  Widget _paletteButton() => Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.keyboard_command_key),
          tooltip: L10n.of(context).commandsTooltip('${commandModifierLabel()}K'),
          onPressed: _openCommandPalette,
        ),
      );

  Widget _sortMenu() => Builder(
        builder: (context) => PopupMenuButton<ShelfSort>(
          icon: const Icon(Icons.sort),
          tooltip: L10n.of(context).sort,
          initialValue: widget.settings.shelfSort,
          onSelected: widget.settings.setShelfSort,
          itemBuilder: (context) => [
            for (final s in ShelfSort.values)
              PopupMenuItem(
                value: s,
                child: Text(
                  L10n.of(context).sortBy(s.label.toLowerCase()),
                ),
              ),
          ],
        ),
      );

  /// Genre filter: lists every genre in the library so you can filter the shelf
  /// to one (or clear it) without opening a book. The icon is tinted while a
  /// filter is active; the active genre also shows as a removable chip below.
  /// Reading-status facet: the "what am I reading / what have I finished"
  /// question, which the genre facet can't answer. Sits next to it and stacks
  /// with it — both are predicates on the same single query.
  Widget _statusMenu() {
    final theme = Theme.of(context);
    final active = _statusFilter != null;
    return PopupMenuButton<String>(
      icon: Icon(
        active ? Icons.bookmark : Icons.bookmark_border,
        color: active ? theme.colorScheme.primary : null,
      ),
      tooltip: L10n.of(context).filterByStatus,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'all',
          onTap: () => setState(() => _statusFilter = null),
          child: Text(
            active
                ? L10n.of(context).anyStatus
                : '${L10n.of(context).anyStatus} ✓',
          ),
        ),
        // Owned states only: "wishlist" isn't a reading status and has its own
        // view (plan 5 #21a).
        for (final status in ReadingStatus.ownedStates)
          PopupMenuItem(
            value: status.name,
            onTap: () => setState(() => _statusFilter = status),
            child: Text(
              '${status.label}${_statusFilter == status ? ' ✓' : ''}',
            ),
          ),
      ],
    );
  }

  Widget _genreMenu() {
    // Only offer genres that actually belong to books currently in the library,
    // so the menu never lists a genre that would match nothing. watchAllBooks
    // gives the valid book ids; watchGenresByBook gives each book's genres.
    return StreamBuilder<List<Book>>(
      stream: repository.watchAllBooks(),
      builder: (context, booksSnap) {
        final bookIds = {
          for (final b in booksSnap.data ?? const <Book>[]) b.id,
        };
        return StreamBuilder<Map<String, List<String>>>(
          stream: repository.watchGenresByBook(),
          builder: (context, snap) {
            final all = <String>{
              for (final e in (snap.data ?? const {}).entries)
                if (bookIds.contains(e.key)) ...e.value,
            }.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            final active = _genreFilter != null;
            final theme = Theme.of(context);
            return PopupMenuButton<String?>(
              icon: Icon(
                active ? Icons.filter_alt : Icons.filter_alt_outlined,
                color: active ? theme.colorScheme.primary : null,
              ),
              tooltip: L10n.of(context).filterByGenre,
              // NOTE: PopupMenuButton.onSelected never fires for a null value
              // (a null pop is indistinguishable from dismissing the menu), so
              // each item clears/sets the filter via its own onTap instead.
              itemBuilder: (context) => [
                if (all.isEmpty)
                  PopupMenuItem<String?>(
                    enabled: false,
                    child: Text(L10n.of(context).noGenresYet),
                  ),
                if (active)
                  PopupMenuItem<String?>(
                    onTap: () => setState(() => _genreFilter = null),
                    child: Text(L10n.of(context).allGenres),
                  ),
                for (final g in all)
                  PopupMenuItem<String?>(
                    onTap: () => setState(() => _genreFilter = g),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check,
                          size: 18,
                          color: g == _genreFilter
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                        ),
                        const SizedBox(width: 8),
                        Text(g),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// A removable chip shown under the app bar while a genre filter is active,
  /// so the filter is visible and can be cleared with one tap.
  Widget _activeGenreBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: InputChip(
          avatar: const Icon(Icons.filter_alt, size: 18),
          label: Text(_genreFilter!),
          onDeleted: () => setState(() => _genreFilter = null),
        ),
      ),
    );
  }

  Widget _shelfTab(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => WallpaperBackground(
        wallpaper: widget.settings.wallpaper,
        // Shelves drive the chip row and decide which scope `watchLibrary`
        // reads (a stored shelf selection can point at a since-deleted
        // shelf); everything else — filtering, sorting, and the
        // authors/genres each book needs — is one further stream, done in
        // SQL rather than re-run in Dart on every rebuild (plan 5 §A1).
        child: StreamBuilder<List<Shelf>>(
          stream: repository.watchShelves(),
          builder: (context, shelvesSnap) {
            final shelves = shelvesSnap.data ?? const [];
            // The stored selection may point at a deleted shelf: fall back to
            // "All" when it no longer exists.
            final storedId = widget.settings.selectedShelfId;
            final active =
                shelves.any((s) => s.id == storedId) ? storedId : null;
            return Column(
              children: [
                if (_genreFilter != null) _activeGenreBar(),
                _shelfChips(shelves, active),
                if (_contentSearchAvailable && _query.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(L10n.of(context).searchTitles),
                          icon: const Icon(Icons.menu_book_outlined),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(L10n.of(context).searchInContents),
                          icon: const Icon(Icons.find_in_page_outlined),
                        ),
                      ],
                      selected: {_searchInsideBooks},
                      onSelectionChanged: (selection) =>
                          setState(() => _searchInsideBooks = selection.first),
                    ),
                  ),
                if (_searchInsideBooks && _query.trim().isNotEmpty)
                  Expanded(
                    child: ContentSearchResults(
                      query: _query,
                      connection: widget.connection,
                      repository: repository,
                      localIndex: _localTextIndex,
                    ),
                  )
                else
                Expanded(
                  child: StreamBuilder<LibraryView>(
                    stream: repository.queries.watchLibrary(
                      shelfId: active,
                      query: _query,
                      genre: _genreFilter,
                      status: _statusFilter?.name,
                      sort: widget.settings.shelfSort,
                    ),
                    builder: (context, snapshot) {
                      final view = snapshot.data ?? LibraryView.empty;
                      return Column(
                        children: [
                          // Derived from the same view the shelf below draws —
                          // never a second query (plan 5 #25).
                          if (!_headerDismissed)
                            LibraryHeader(
                              highlights: LibraryHighlights.from(view),
                              onOpen: _openBook,
                              onDismiss: () =>
                                  setState(() => _headerDismissed = true),
                            ),
                          Expanded(child: _shelfBody(view, active != null)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _shelfBody(LibraryView view, bool onCustomShelf) {
    final theme = Theme.of(context);
    final entries = view.entries;
    if (entries.isEmpty) {
      // view.scopeEmpty is true only when the shelf/library itself has zero
      // books, independent of any active filter — so a search or genre facet
      // that merely matches nothing still gets the "no match" message below,
      // exactly like the shelf genuinely being empty gets its own message.
      if (!view.scopeEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _noMatchMessage(L10n.of(context)),
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              // A dead end otherwise: the filters that hid everything aren't
              // necessarily both visible from here (plan 5 #41).
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _genreFilter = null;
                  });
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: Text(L10n.of(context).clearSearchAndFilters),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 56,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              onCustomShelf
                  ? L10n.of(context).customShelfEmptyTitle
                  : L10n.of(context).shelfEmptyTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              onCustomShelf
                  ? L10n.of(context).customShelfEmptyBody
                  : L10n.of(context).shelfEmptyBody,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (!onCustomShelf) ...[
              const SizedBox(height: 16),
              // The two ways in that a bare FAB doesn't advertise (plan 5 #41).
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openAddBook(context),
                    icon: const Icon(Icons.add),
                    label: Text(L10n.of(context).addABook),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FolderImportPage(
                          repository: repository,
                          settings: widget.settings,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.folder_open),
                    label: Text(L10n.of(context).importFolder),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }
    // The list is a different widget rather than a mode inside ShelfView: it
    // needs the whole entry (author, whether there is a file) where the shelf
    // needs only the book, and a shelf that drew no shelves would be a shelf
    // in name only.
    if (widget.settings.bookFace == BookFace.list) {
      return BookListView(
        entries: entries,
        selected: _selection,
        onToggleSelected: _toggleSelected,
        selectionMode: _selection.isNotEmpty,
        detailBuilder: (book) => BookDetailPage(
          book: book,
          repository: repository,
          settings: widget.settings,
          connection: widget.connection,
          onGenreTap: _applyGenreFilter,
        ),
      );
    }
    return ShelfView(
      books: [for (final e in entries) e.book],
      selected: _selection,
      onToggleSelected: _toggleSelected,
      selectionMode: _selection.isNotEmpty,
      bookFace: widget.settings.bookFace,
      spineArt: widget.settings.spineArt,
      material: widget.settings.shelfMaterial,
      typography: widget.settings.spineTypography,
      coverFileOf: repository.coverFileOf,
      detailBuilder: (book) => BookDetailPage(
        book: book,
        repository: repository,
        settings: widget.settings,
        connection: widget.connection,
        onGenreTap: _applyGenreFilter,
      ),
    );
  }

  /// Explains why the shelf is empty given the active genre filter and/or
  /// search text, so the message matches whichever controls are in effect.
  String _noMatchMessage(L10n l10n) {
    final q = _query.trim();
    final genre = _genreFilter;
    if (genre != null && q.isNotEmpty) {
      return l10n.noBooksInGenreMatch(genre, q);
    }
    if (genre != null) return l10n.noBooksInGenre(genre);
    return l10n.noBooksMatch(q);
  }

  /// The horizontal chip row: All + each shelf + "New shelf". Selecting a chip
  /// filters the shelf below; long-press a shelf chip to rename or delete it.
  Widget _shelfChips(List<Shelf> shelves, String? active) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: ChoiceChip(
              label: Text(L10n.of(context).shelfAll),
              selected: active == null,
              onSelected: (_) => widget.settings.setSelectedShelfId(null),
            ),
          ),
          for (final shelf in shelves)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: GestureDetector(
                onLongPress: () => _shelfMenu(shelf),
                child: ChoiceChip(
                  label: Text(shelf.name),
                  selected: active == shelf.id,
                  onSelected: (_) =>
                      widget.settings.setSelectedShelfId(shelf.id),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(L10n.of(context).shelfNew),
              onPressed: _promptNewShelf,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptNewShelf() async {
    final name = await _promptShelfName('New shelf');
    if (name == null || name.isEmpty) return;
    final id = await repository.createShelf(name);
    await widget.settings.setSelectedShelfId(id);
  }

  Future<void> _shelfMenu(Shelf shelf) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(L10n.of(context).renameShelf),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(L10n.of(context).deleteShelf),
              subtitle: Text(L10n.of(context).deleteShelfSubtitle),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      final name = await _promptShelfName('Rename shelf', initial: shelf.name);
      if (name != null && name.isNotEmpty) {
        await repository.renameShelf(shelf.id, name);
      }
    } else if (action == 'delete') {
      if (widget.settings.selectedShelfId == shelf.id) {
        await widget.settings.setSelectedShelfId(null);
      }
      await repository.deleteShelf(shelf.id);
    }
  }

  Future<String?> _promptShelfName(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              InputDecoration(hintText: L10n.of(context).shelfNameHint),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(L10n.of(context).save),
          ),
        ],
      ),
    );
  }
}
