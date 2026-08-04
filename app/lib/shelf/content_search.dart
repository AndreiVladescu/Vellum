import 'dart:async';

import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../data/local_text_index.dart';
import '../reader/reader_page.dart';
import '../server/connection_store.dart';
import '../server/server_client.dart';

/// Searching inside book contents (plan 5 #32).
///
/// `book_search` covers titles, authors and genres and is the default, because
/// it works offline and always will. This searches the *text* of the books,
/// from whichever index is available:
///
/// - **[localIndex] when there is one.** On desktop, with the setting on, the
///   text of the local files is indexed here — see `local_text_index.dart` for
///   why the "only a server can do this" reasoning stops at a phone. Preferred
///   when present because it works offline *and* because every hit is in a file
///   this device actually holds, so "open at the page" always has something to
///   open.
/// - **The server otherwise**, when it advertises `content_search`.
///
/// With neither, the tab isn't offered at all.
class ContentSearchResults extends StatefulWidget {
  const ContentSearchResults({
    super.key,
    required this.query,
    required this.connection,
    required this.repository,
    this.localIndex,
  });

  final String query;
  final ServerConnection connection;
  final LibraryRepository repository;

  /// The on-device index, or null to search the server instead.
  final LocalTextIndex? localIndex;

  @override
  State<ContentSearchResults> createState() => _ContentSearchResultsState();
}

class _ContentSearchResultsState extends State<ContentSearchResults> {
  List<ContentHit>? _hits;
  String? _error;
  bool _busy = false;
  Timer? _debounce;

  /// The query the in-flight (or last completed) request was for, so a slow
  /// response for "dun" can't overwrite the results for "dune".
  String _inFlight = '';

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ContentSearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    // A local index is one SQLite query, so it can keep up with typing; the
    // server path is a network round trip and an FTS query on someone else's
    // machine, and earns the longer wait.
    _debounce = Timer(
      Duration(milliseconds: widget.localIndex == null ? 350 : 150),
      _run,
    );
  }

  Future<void> _run() async {
    final query = widget.query.trim();
    if (query.length < 2) {
      setState(() {
        _hits = const [];
        _error = null;
      });
      return;
    }
    final local = widget.localIndex;
    if (local != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      _inFlight = query;
      final found = await local.search(query);
      if (!mounted || _inFlight != query) return;
      setState(() {
        // `fileId` is only used by the server path's own bookkeeping; a local
        // hit is resolved through the book's files on disk instead.
        _hits = [
          for (final h in found)
            ContentHit(
              bookId: h.bookId,
              title: h.title,
              fileId: '',
              page: h.page,
              snippet: h.snippet,
            ),
        ];
        _busy = false;
      });
      return;
    }
    final client = widget.connection.client;
    if (client == null) {
      setState(() => _error = 'Not connected to a server.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _inFlight = query;
    try {
      final hits = await client.searchContents(query);
      if (!mounted || _inFlight != query) return;
      setState(() {
        _hits = hits;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || _inFlight != query) return;
      setState(() {
        _busy = false;
        _error = e is ServerException
            ? "This server can't search inside books."
            : "Couldn't reach the server.";
      });
    }
  }

  /// Opens the book at the page that matched.
  ///
  /// Only possible when the book has a local PDF: the hit names a page in the
  /// *server's* copy, and there is nothing to open here otherwise. Said plainly
  /// rather than opening the book at page one and hoping.
  Future<void> _open(ContentHit hit) async {
    final book = await widget.repository.watchBook(hit.bookId).first;
    if (!mounted) return;
    if (book == null) {
      _say('That book isn’t on this device yet — sync, then try again.');
      return;
    }
    final files = await widget.repository.watchFilesOf(book.id).first;
    if (!mounted) return;
    final pdf = files.where((f) => f.format == 'pdf').firstOrNull;
    if (pdf == null) {
      _say('No local PDF for “${book.title}” to open at page ${hit.page}.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderPage(
        book: book,
        file: widget.repository.fileOf(pdf),
        repository: widget.repository,
        initialPage: hit.page,
      ),
    ));
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return _Message(icon: Icons.cloud_off, text: _error!);
    }
    final hits = _hits;
    if (hits == null || (_busy && hits.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.query.trim().length < 2) {
      return const _Message(
        icon: Icons.search,
        text: 'Type at least two letters to search inside your books.',
      );
    }
    if (hits.isEmpty) {
      return _Message(
        icon: Icons.search_off,
        text: widget.localIndex == null
            ? 'No book on the server contains “${widget.query.trim()}”.'
            : 'No indexed book contains “${widget.query.trim()}”.',
      );
    }
    return ListView.separated(
      itemCount: hits.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final hit = hits[i];
        return ListTile(
          leading: const Icon(Icons.find_in_page_outlined),
          title: Text(hit.title),
          subtitle: _Snippet(raw: hit.snippet),
          trailing: Text(
            'p. ${hit.page}',
            style: theme.textTheme.labelMedium,
          ),
          onTap: () => _open(hit),
        );
      },
    );
  }
}

/// Renders FTS5's `[match]` markers as bold text.
///
/// The brackets are what `snippet()` was told to emit; showing them raw would
/// leak an implementation detail into what reads like prose from the book.
class _Snippet extends StatelessWidget {
  const _Snippet({required this.raw});

  final String raw;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final spans = <TextSpan>[];
    var rest = raw;
    while (true) {
      final open = rest.indexOf('[');
      final close = open == -1 ? -1 : rest.indexOf(']', open);
      if (open == -1 || close == -1) {
        spans.add(TextSpan(text: rest));
        break;
      }
      spans
        ..add(TextSpan(text: rest.substring(0, open)))
        ..add(TextSpan(
          text: rest.substring(open + 1, close),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      rest = rest.substring(close + 1);
    }
    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
