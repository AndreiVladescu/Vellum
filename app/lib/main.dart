import 'package:flutter/material.dart';

import 'account/user_profile.dart';
import 'add_book/add_book_page.dart';
import 'app_drawer.dart';
import 'book_detail/book_detail_page.dart';
import 'data/database.dart';
import 'data/library_repository.dart';
import 'shelf/shelf_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await LibraryRepository.open(VellumDatabase());
  final profile = await UserProfileStore.load();
  runApp(VellumApp(repository: repository, profile: profile));
}

class VellumApp extends StatelessWidget {
  const VellumApp({super.key, required this.repository, required this.profile});

  final LibraryRepository repository;
  final UserProfileStore profile;

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
      home: LibraryPage(repository: repository, profile: profile),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage(
      {super.key, required this.repository, required this.profile});

  final LibraryRepository repository;
  final UserProfileStore profile;

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
      drawer: AppDrawer(profile: widget.profile),
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
      body: Container(
        // A warm, library-like backdrop instead of the flat theme color:
        // soft parchment in light mode, dim candle-lit tones in dark mode.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: Theme.of(context).brightness == Brightness.dark
                ? const [Color(0xFF262019), Color(0xFF171310)]
                : const [Color(0xFFFAF4E8), Color(0xFFEBDCC3)],
          ),
        ),
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
              return Center(child: Text('No books match “${_query.trim()}”.'));
            }
            return ShelfView(
              books: books,
              coverFileOf: repository.coverFileOf,
              detailBuilder: (book) =>
                  BookDetailPage(book: book, repository: repository),
            );
          },
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
