import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/settings/shelf_sort.dart';
import 'package:vellum/shelf/shelf_filter.dart';

void main() {
  test('filters by title, author, and genre token', () async {
    final dir = Directory.systemTemp.createTempSync('vellum_filter_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
    await db
        .into(db.books)
        .insert(BooksCompanion.insert(id: 'b2', title: 'Neuromancer'));
    await repo.setAuthors('b1', ['Frank Herbert']);
    await repo.setAuthors('b2', ['William Gibson']);
    await repo.setGenres('b1', ['Sci-Fi', 'Classic']);
    await repo.setGenres('b2', ['Cyberpunk']);

    final books = await repo.watchAllBooks().first;
    final authors = await repo.watchAuthorsByBook().first;
    final genres = await repo.watchGenresByBook().first;

    List<String> ids(String q) => [
          for (final b in filterBooks(
            books: books,
            query: q,
            authorsByBook: authors,
            genresByBook: genres,
          ))
            b.id
        ];

    expect(ids('dune'), ['b1'], reason: 'title match');
    expect(ids('gibson'), ['b2'], reason: 'author match');
    expect(ids('genre:cyber'), ['b2'], reason: 'genre token match');
    expect(ids('genre:sci'), ['b1']);
    expect(ids(''), ['b1', 'b2'], reason: 'empty query returns all');
    expect(ids('nothingmatches'), isEmpty);
  });

  test('sorts by title, author, and year with missing keys last', () async {
    final dir = Directory.systemTemp.createTempSync('vellum_sort_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dir);
    final db = repo.db;
    // Zed (2000, Bunch), Alpha (1990, no author), Mid (no year, Adams).
    await db.into(db.books).insert(BooksCompanion.insert(
        id: 'z', title: 'Zed', publishedYear: const Value(2000)));
    await db.into(db.books).insert(BooksCompanion.insert(
        id: 'a', title: 'Alpha', publishedYear: const Value(1990)));
    await db.into(db.books).insert(BooksCompanion.insert(id: 'm', title: 'Mid'));
    await repo.setAuthors('z', ['Bunch']);
    await repo.setAuthors('m', ['Adams']);

    final books = await repo.watchAllBooks().first;
    final authors = await repo.watchAuthorsByBook().first;
    List<String> ids(ShelfSort s) => [
          for (final b
              in sortBooks(books: books, sort: s, authorsByBook: authors))
            b.id
        ];

    expect(ids(ShelfSort.title), ['a', 'm', 'z']);
    expect(ids(ShelfSort.year), ['a', 'z', 'm'],
        reason: '1990, 2000, then the year-less book last');
    expect(ids(ShelfSort.author), ['m', 'z', 'a'],
        reason: 'Adams, Bunch, then the author-less book last');
  });
}
