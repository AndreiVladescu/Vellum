import 'package:flutter/material.dart';

import 'data/database.dart';

void main() {
  runApp(VellumApp(database: VellumDatabase()));
}

class VellumApp extends StatelessWidget {
  const VellumApp({super.key, required this.database});

  final VellumDatabase database;

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
      home: LibraryPage(database: database),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.database});

  final VellumDatabase database;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vellum')),
      body: StreamBuilder<List<Book>>(
        stream: database.watchAllBooks(),
        builder: (context, snapshot) {
          final books = snapshot.data ?? const [];
          if (books.isEmpty) {
            return const Center(
              child: Text('Your shelf is empty.\nAdd your first book!',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return ListTile(
                leading: const Icon(Icons.book_outlined),
                title: Text(book.title),
                subtitle: book.subtitle == null ? null : Text(book.subtitle!),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add a test book',
        onPressed: () {
          final n = DateTime.now().millisecondsSinceEpoch;
          database.into(database.books).insert(BooksCompanion.insert(
                id: 'book-$n',
                title: 'Test Book $n',
              ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
