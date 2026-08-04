import 'package:flutter/material.dart';

import '../book_detail/book_detail_page.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../server/connection_store.dart';
import '../settings/app_settings.dart';

/// Everything you hold by one author.
///
/// Reached by tapping the author's name on a book's page, which until now was
/// plain text. Genres have been tappable for a while and authors were not,
/// which is the wrong way round: "what else of theirs do I have" is a far more
/// common thought than "what else is filed under Science Fiction".
///
/// Wishlist entries are shown alongside owned books rather than hidden, marked
/// as wanted — half the point of looking an author up is spotting the ones you
/// have already decided to get.
class AuthorPage extends StatelessWidget {
  const AuthorPage({
    super.key,
    required this.author,
    required this.repository,
    this.settings,
    this.connection,
  });

  final String author;
  final LibraryRepository repository;
  final AppSettingsStore? settings;
  final ServerConnection? connection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(author)),
      body: StreamBuilder<List<Book>>(
        stream: repository.queries.watchBooksByAuthor(author),
        builder: (context, snapshot) {
          final books = snapshot.data;
          if (books == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (books.isEmpty) {
            return const Center(child: Text('No books by this author.'));
          }
          final owned = books.where((b) => b.status != 'wishlist').length;
          return ListView.separated(
            itemCount: books.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    [
                      '$owned on your shelf',
                      if (books.length > owned)
                        '${books.length - owned} on the wishlist',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
              final book = books[i - 1];
              return _BookTile(
                book: book,
                repository: repository,
                settings: settings,
                connection: connection,
              );
            },
          );
        },
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.repository,
    this.settings,
    this.connection,
  });

  final Book book;
  final LibraryRepository repository;
  final AppSettingsStore? settings;
  final ServerConnection? connection;

  @override
  Widget build(BuildContext context) {
    final wanted = book.status == 'wishlist';
    final status = ReadingStatus.values
        .where((s) => s.name == book.status)
        .firstOrNull;
    return ListTile(
      leading: Icon(
        wanted ? Icons.bookmark_border : Icons.menu_book_outlined,
      ),
      title: Text(book.title),
      subtitle: Text([
        if (book.publishedYear != null) '${book.publishedYear}',
        if (wanted) 'On your wishlist' else if (status != null) status.label,
      ].join(' · ')),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BookDetailPage(
          book: book,
          repository: repository,
          settings: settings,
          connection: connection,
        ),
      )),
    );
  }
}
