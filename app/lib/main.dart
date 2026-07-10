import 'dart:async';

import 'package:flutter/material.dart';

import 'account/user_profile.dart';
import 'add_book/add_book_page.dart';
import 'app_drawer.dart';
import 'book_detail/book_detail_page.dart';
import 'data/database.dart';
import 'data/library_repository.dart';
import 'physical/physical_libraries_page.dart';
import 'server/connection_store.dart';
import 'settings/app_settings.dart';
import 'settings/wallpaper.dart';
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

  LibraryRepository get repository => widget.repository;

  @override
  void dispose() {
    _searchDebounce?.cancel();
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

  List<Book> _filter(List<Book> books) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return books;
    return [
      for (final b in books)
        if (b.title.toLowerCase().contains(q) ||
            (b.subtitle?.toLowerCase().contains(q) ?? false))
          b,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(
        profile: widget.profile,
        settings: widget.settings,
        connection: widget.connection,
        repository: widget.repository,
      ),
      appBar: _tab == 0
          ? AppBar(
              title: TextField(
                onChanged: _onQueryChanged,
                decoration: const InputDecoration(
                  hintText: 'Search your shelf…',
                  icon: Icon(Icons.search),
                  border: InputBorder.none,
                ),
              ),
            )
          : AppBar(title: const Text('Physical libraries')),
      body: IndexedStack(
        index: _tab,
        children: [
          _shelfTab(context),
          PhysicalLibrariesTab(repository: repository),
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
              onPressed: () => promptCreateLibrary(context, repository),
              icon: const Icon(Icons.add),
              label: const Text('New library'),
            ),
    );
  }

  Widget _shelfTab(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => WallpaperBackground(
        wallpaper: widget.settings.wallpaper,
        child: StreamBuilder<List<Book>>(
          stream: repository.watchAllBooks(),
          builder: (context, snapshot) {
            final all = snapshot.data ?? const [];
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
                    Text('Your shelf is empty',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Add your first book to see it here.',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            }
            final books = _filter(all);
            if (books.isEmpty) {
              return Center(
                child: Text(
                  'No books match “${_query.trim()}”.',
                  style:
                      TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            }
            return ShelfView(
              books: books,
              bookFace: widget.settings.bookFace,
              coverFileOf: repository.coverFileOf,
              detailBuilder: (book) =>
                  BookDetailPage(book: book, repository: repository),
            );
          },
        ),
      ),
    );
  }
}
