import 'dart:async';

import 'package:flutter/material.dart';

import 'account/user_profile.dart';
import 'add_book/add_book_page.dart';
import 'app_drawer.dart';
import 'book_detail/book_detail_page.dart';
import 'data/database.dart';
import 'data/library_repository.dart';
import 'physical/physical_libraries_page.dart';
import 'server/auto_pusher.dart';
import 'server/connection_store.dart';
import 'server/server_client.dart';
import 'server/sync_service.dart';
import 'settings/app_settings.dart';
import 'settings/shelf_sort.dart';
import 'settings/wallpaper.dart';
import 'shelf/shelf_filter.dart';
import 'shelf/shelf_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF7A5C3E),
        brightness: Brightness.dark,
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
  int _tab = 0; // 0 = digital shelf, 1 = physical libraries
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

  LibraryRepository get repository => widget.repository;

  @override
  void initState() {
    super.initState();
    _autoSync();
    _autoPusher.start();
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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _autoPusher.dispose();
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
      MaterialPageRoute(builder: (_) => AddBookPage(repository: repository)),
    );
    if (addedTitle != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“$addedTitle” added to your shelf')),
      );
    }
  }

  List<Book> _filter(
    List<Book> books,
    Map<String, List<String>> authorsByBook,
    Map<String, List<String>> genresByBook,
  ) =>
      filterBooks(
        books: books,
        query: _query,
        authorsByBook: authorsByBook,
        genresByBook: genresByBook,
      );

  /// Applies a `genre:` filter from a tapped genre chip: fills the search box
  /// (so it's visible and clearable) and refreshes the shelf.
  void _applyGenreFilter(String genre) {
    _searchDebounce?.cancel();
    final query = 'genre:$genre';
    _searchController.text = query;
    setState(() => _query = query);
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
                  hintText: 'Search title, author, or genre:…',
                  icon: Icon(Icons.search),
                  border: InputBorder.none,
                ),
              ),
              actions: [_sortMenu()],
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
          ? FloatingActionButton.extended(
              onPressed: () => _openAddBook(context),
              icon: const Icon(Icons.add),
              label: const Text('Add book'),
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

  Widget _shelfTab(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => WallpaperBackground(
        wallpaper: widget.settings.wallpaper,
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
                _shelfChips(shelves, active),
                Expanded(
                  child: StreamBuilder<Map<String, List<String>>>(
                    stream: repository.watchAuthorsByBook(),
                    builder: (context, authorsSnap) {
                      final authors = authorsSnap.data ?? const {};
                      return StreamBuilder<Map<String, List<String>>>(
                        stream: repository.watchGenresByBook(),
                        builder: (context, genresSnap) {
                          final genres = genresSnap.data ?? const {};
                          return StreamBuilder<List<Book>>(
                            stream: active == null
                                ? repository.watchAllBooks()
                                : repository.watchBooksOnShelf(active),
                            builder: (context, snapshot) => _shelfBody(
                              snapshot.data ?? const [],
                              active != null,
                              authors,
                              genres,
                            ),
                          );
                        },
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

  Widget _shelfBody(
    List<Book> all,
    bool onCustomShelf,
    Map<String, List<String>> authorsByBook,
    Map<String, List<String>> genresByBook,
  ) {
    final theme = Theme.of(context);
    if (all.isEmpty) {
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
          ],
        ),
      );
    }
    final books = sortBooks(
      books: _filter(all, authorsByBook, genresByBook),
      sort: widget.settings.shelfSort,
      authorsByBook: authorsByBook,
    );
    if (books.isEmpty) {
      return Center(
        child: Text(
          'No books match “${_query.trim()}”.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ShelfView(
      books: books,
      bookFace: widget.settings.bookFace,
      spineArt: widget.settings.spineArt,
      coverFileOf: repository.coverFileOf,
      detailBuilder: (book) => BookDetailPage(
        book: book,
        repository: repository,
        onGenreTap: _applyGenreFilter,
      ),
    );
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
