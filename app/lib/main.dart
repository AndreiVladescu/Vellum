import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account/user_profile.dart';
import 'add_book/add_book_page.dart';
import 'add_book/scan_page.dart';
import 'app_drawer.dart';
import 'book_detail/book_detail_page.dart';
import 'data/database.dart';
import 'data/library_queries.dart';
import 'data/library_repository.dart';
import 'import/filename_metadata.dart';
import 'import/folder_import_page.dart';
import 'import/folder_import_service.dart';
import 'import/import_plan.dart';
import 'import/incoming_share.dart';
import 'onboarding/first_run_sheet.dart';
import 'physical/physical_libraries_page.dart';
import 'server/auto_pusher.dart';
import 'server/connection_store.dart';
import 'server/server_client.dart';
import 'server/server_page.dart';
import 'server/sync_service.dart';
import 'settings/app_settings.dart';
import 'settings/shelf_sort.dart';
import 'settings/wallpaper.dart';
import 'shelf/library_header.dart';
import 'shelf/shelf_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status/nav bars. Android 15 (targetSdk 35) enforces this
  // anyway; setting it explicitly makes earlier Android versions match. The
  // Material scaffolding (AppBar, NavigationBar, FAB, bottom sheets) already
  // insets itself; custom bottom bars use SafeArea (see the EPUB reader).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final repository = await LibraryRepository.open(VellumDatabase());
  final profile = await UserProfileStore.load();
  final settings = await AppSettingsStore.load();
  final connection = await ServerConnection.load();
  runApp(VellumApp(
    repository: repository,
    profile: profile,
    settings: settings,
    connection: connection,
  ));
}

class VellumApp extends StatelessWidget {
  const VellumApp({
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vellum',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7A5C3E), // leather-ish brown
        brightness: Brightness.light,
        // Guarantee ≥48dp tap targets on every platform (not just the mobile
        // default) so touch/accessibility targets are always reachable.
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF7A5C3E),
        brightness: Brightness.dark,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      home: LibraryPage(
        repository: repository,
        profile: profile,
        settings: settings,
        connection: connection,
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
  });

  final LibraryRepository repository;
  final UserProfileStore profile;
  final AppSettingsStore settings;
  final ServerConnection connection;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _query = '';
  // The active genre facet, or null for "all genres". Kept separate from the
  // text query so a genre filter and a text search can be on at once, and so it
  // can be shown/cleared as a chip rather than hidden in the search box.
  String? _genreFilter;
  // The reading-status facet (plan 5 #18), or null for "any status".
  ReadingStatus? _statusFilter;
  int _tab = 0; // 0 = digital shelf, 1 = physical libraries
  // The continue-reading / recently-added strip (plan 5 #25), hidden for this
  // session only: its value is reappearing when you come back mid-book, not
  // being a preference to manage.
  bool _headerDismissed = false;
  Timer? _searchDebounce;
  final _searchController = TextEditingController();

  // One sync service for the whole app (launch auto-sync + the server page),
  // so its re-entrancy guard spans every way a sync can start.
  late final SyncService _sync = SyncService(widget.repository);

  // Debounced background push of dirty books while connected, so a long editing
  // session keeps the server/console fresh without waiting for the next launch.
  late final AutoPusher _autoPusher = AutoPusher(
    repository: widget.repository,
    sync: _sync,
    client: () => widget.connection.client,
    enabled: () => widget.settings.autoPush,
  );

  /// Books opened or shared into Vellum from another app (plan 5 #20).
  late final IncomingShare _incoming = IncomingShare();
  StreamSubscription<List<String>>? _incomingSub;

  LibraryRepository get repository => widget.repository;

  @override
  void initState() {
    super.initState();
    _autoSync();
    _autoPusher.start();
    _offerWatchedFolder();
    _listenForSharedBooks();
    _showFirstRun();
    // Catch up covers that predate dominant-colour extraction (no-op once done).
    widget.repository.backfillCoverColors();
  }

  /// Best-effort sync on launch when a server is connected. Quiet by design:
  /// the app is local-first, so an unreachable server is normal — only a
  /// result worth knowing about (changes or issues) surfaces a snackbar.
  Future<void> _autoSync() async {
    final conn = widget.connection;
    final client = conn.client;
    if (client == null) return;
    try {
      final report = await _sync.sync(
        client,
        cursor: conn.syncCursor,
        onCursor: conn.setSyncCursor,
      );
      // Reading position rides its own pass, after the sync guard is free and
      // only when the user opted in (plan 5 #5). Its own try/catch: a failure
      // here must not make a successful library sync look failed.
      await _syncReadingPosition(client);
      if (!mounted) return;
      final changed = report.pulled +
          report.pushed +
          report.deletedLocally +
          report.deletedRemotely;
      if (changed == 0 && !report.hasIssues) return;
      final n = report.issues.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced — pulled ${report.pulled}, pushed ${report.pushed}'
            '${report.hasIssues ? ', $n issue${n == 1 ? '' : 's'}' : ''}.',
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('$unseen new file${unseen == 1 ? '' : 's'} in your '
            'watched folder.'),
        action: SnackBarAction(
          label: 'Review',
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
          SnackBar(content: Text('“$added” added to your shelf')),
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
    _autoPusher.dispose();
    _incomingSub?.cancel();
    _incoming.dispose();
    super.dispose();
  }

  // Re-packing the shelf rows on every keystroke is expensive; wait for a
  // short pause in typing before filtering.
  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _query = value);
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
        SnackBar(content: Text('“$addedTitle” added to your shelf')),
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
        setState(() => _tab = 1);
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
        onGenreTap: _applyGenreFilter,
      ),
    ));
  }

  /// Applies the genre facet from a tapped genre chip on a book's detail page.
  /// Sets the dedicated filter (shown as a removable chip near the search)
  /// rather than the search box, so any text search you had stays put.
  void _applyGenreFilter(String genre) {
    setState(() => _genreFilter = genre);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(
        profile: widget.profile,
        settings: widget.settings,
        connection: widget.connection,
        repository: widget.repository,
        sync: _sync,
      ),
      appBar: _tab == 0
          ? AppBar(
              title: TextField(
                controller: _searchController,
                onChanged: _onQueryChanged,
                decoration: const InputDecoration(
                  hintText: 'Search your library…',
                  icon: Icon(Icons.search),
                  border: InputBorder.none,
                ),
              ),
              actions: [_statusMenu(), _genreMenu(), _sortMenu()],
            )
          : AppBar(title: const Text('Physical libraries')),
      body: IndexedStack(
        index: _tab,
        children: [
          _shelfTab(context),
          PhysicalLibrariesTab(
            repository: repository,
            settings: widget.settings,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Shelf',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Physical',
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
                  tooltip: 'Scan an ISBN barcode',
                  onPressed: () => _openScan(context),
                  child: const Icon(Icons.barcode_reader),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'add',
                  onPressed: () => _openAddBook(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add book'),
                ),
              ],
            )
          : FloatingActionButton.extended(
              onPressed: () =>
                  promptCreateLibrary(context, repository, widget.settings),
              icon: const Icon(Icons.add),
              label: const Text('New library'),
            ),
    );
  }

  Widget _sortMenu() => PopupMenuButton<ShelfSort>(
        icon: const Icon(Icons.sort),
        tooltip: 'Sort',
        initialValue: widget.settings.shelfSort,
        onSelected: widget.settings.setShelfSort,
        itemBuilder: (context) => [
          for (final s in ShelfSort.values)
            PopupMenuItem(
              value: s,
              child: Text('Sort by ${s.label.toLowerCase()}'),
            ),
        ],
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
      tooltip: 'Filter by reading status',
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'all',
          onTap: () => setState(() => _statusFilter = null),
          child: Text(active ? 'Any status' : 'Any status ✓'),
        ),
        for (final status in ReadingStatus.values)
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
              tooltip: 'Filter by genre',
              // NOTE: PopupMenuButton.onSelected never fires for a null value
              // (a null pop is indistinguishable from dismissing the menu), so
              // each item clears/sets the filter via its own onTap instead.
              itemBuilder: (context) => [
                if (all.isEmpty)
                  const PopupMenuItem<String?>(
                    enabled: false,
                    child: Text('No genres yet'),
                  ),
                if (active)
                  PopupMenuItem<String?>(
                    onTap: () => setState(() => _genreFilter = null),
                    child: const Text('All genres'),
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
                _noMatchMessage(),
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
                label: const Text('Clear search and filters'),
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
            Text(onCustomShelf ? 'This shelf is empty' : 'Your shelf is empty',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              onCustomShelf
                  ? 'Add books to it from their detail page.'
                  : 'Add your first book to see it here.',
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
                    label: const Text('Add a book'),
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
                    label: const Text('Import a folder'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }
    return ShelfView(
      books: [for (final e in entries) e.book],
      bookFace: widget.settings.bookFace,
      spineArt: widget.settings.spineArt,
      coverFileOf: repository.coverFileOf,
      detailBuilder: (book) => BookDetailPage(
        book: book,
        repository: repository,
        settings: widget.settings,
        onGenreTap: _applyGenreFilter,
      ),
    );
  }

  /// Explains why the shelf is empty given the active genre filter and/or
  /// search text, so the message matches whichever controls are in effect.
  String _noMatchMessage() {
    final q = _query.trim();
    final genre = _genreFilter;
    if (genre != null && q.isNotEmpty) {
      return 'No “$genre” books match “$q”.';
    }
    if (genre != null) return 'No books tagged “$genre”.';
    return 'No books match “$q”.';
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
              label: const Text('All'),
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
              label: const Text('New shelf'),
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
              title: const Text('Rename shelf'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete shelf'),
              subtitle: const Text('The books stay in your library'),
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
          decoration: const InputDecoration(hintText: 'Shelf name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
