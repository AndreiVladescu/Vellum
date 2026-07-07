import 'package:flutter/material.dart';

import 'account/user_profile.dart';
import 'add_book/add_book_page.dart';
import 'app_drawer.dart';
import 'book_detail/book_detail_page.dart';
import 'data/database.dart';
import 'data/library_repository.dart';
import 'settings/app_settings.dart';
import 'settings/wallpaper.dart';
import 'shelf/shelf_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await LibraryRepository.open(VellumDatabase());
  final profile = await UserProfileStore.load();
  final settings = await AppSettingsStore.load();
  runApp(VellumApp(
      repository: repository, profile: profile, settings: settings));
}

class VellumApp extends StatelessWidget {
  const VellumApp({
    super.key,
    required this.repository,
    required this.profile,
    required this.settings,
  });

  final LibraryRepository repository;
  final UserProfileStore profile;
  final AppSettingsStore settings;

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
          repository: repository, profile: profile, settings: settings),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.repository,
    required this.profile,
    required this.settings,
  });

  final LibraryRepository repository;
  final UserProfileStore profile;
  final AppSettingsStore settings;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _query = '';

  LibraryRepository get repository => widget.repository;

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
      drawer: AppDrawer(profile: widget.profile, settings: widget.settings),
      appBar: AppBar(
        title: TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            hintText: 'Search your shelf…',
            icon: Icon(Icons.search),
            border: InputBorder.none,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => WallpaperBackground(
          wallpaper: widget.settings.wallpaper,
          child: StreamBuilder<List<Book>>(
            stream: repository.watchAllBooks(),
            builder: (context, snapshot) {
              final all = snapshot.data ?? const [];
              if (all.isEmpty) {
                return const Center(
                  child: Text('Your shelf is empty.\nAdd your first book!',
                      textAlign: TextAlign.center),
                );
              }
              final books = _filter(all);
              if (books.isEmpty) {
                return Center(
                    child: Text('No books match “${_query.trim()}”.'));
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddBook(context),
        icon: const Icon(Icons.add),
        label: const Text('Add book'),
      ),
    );
  }
}
