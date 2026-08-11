import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../import/import_plan.dart';
import 'barcode_camera.dart';
import 'isbn.dart';

/// One book added during a scanning session, for the running strip and undo.
class ScannedBook {
  ScannedBook({
    required this.bookId,
    required this.isbn13,
    required this.title,
    this.duplicateOf,
    this.wanted = false,
  });

  final String bookId;
  final String isbn13;
  final String title;

  /// True when this scan went to the wishlist rather than the library
  /// (plan 5 #21a) — the bookshop case, where you scan what you're holding
  /// without claiming to have bought it.
  final bool wanted;

  /// Title of an existing book this one looks like, if any. The book is still
  /// added — the scan is the user's assertion that they hold a copy — but it is
  /// flagged so a mistake is obvious immediately rather than at the next tidy-up.
  final String? duplicateOf;
}

/// Continuous ISBN scanning (plan 5 #16), the last unbuilt half of `DESIGN.md`'s
/// build-order item 6 and the main reason to have Vellum on a phone.
///
/// Shape of the feature, and why:
///
/// - **The camera stays live.** Cataloguing a shelf is dozens of scans; a modal
///   confirmation per book would make it unusable. Each accepted barcode adds a
///   book and slides onto a running strip with an undo.
/// - **Barcodes are validated before any lookup** ([toIsbn13]). A camera pointed
///   at a desk finds all sorts of EAN-13s, and a "not found" for each one would
///   feel like a broken feature rather than a non-book.
/// - **Duplicates are flagged, not blocked**, reusing #15's classifier: someone
///   may genuinely own two copies, and refusing the scan would be wrong.
/// - **It degrades instead of dead-ending.** No camera (desktop) or a denied
///   permission leaves a manual ISBN field driving exactly the same code path.
class ScanPage extends StatefulWidget {
  const ScanPage({
    super.key,
    required this.repository,
    this.barcodes,
    this.cameraAvailable,
    this.initialWishlist = false,
  });

  final LibraryRepository repository;

  /// Whether the session starts in wishlist mode. The toggle is on screen
  /// either way; this is for opening the scanner straight from the wishlist.
  final bool initialWishlist;

  /// Barcode source. Null means "use the device camera"; a stream can be
  /// supplied instead, which is how the flow is tested without a camera.
  final Stream<String>? barcodes;

  /// Whether to show the camera preview at all. Defaults to true on Android/iOS
  /// and false elsewhere — a desktop gets the manual field.
  final bool? cameraAvailable;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _manualIsbn = TextEditingController();
  final _added = <ScannedBook>[];

  /// Barcodes already handled this session, so the camera re-reading the same
  /// book twenty times a second adds it once. Session-scoped on purpose: a user
  /// who really wants a second copy can scan it again after a restart, and the
  /// duplicate flag tells them what happened either way.
  final _seen = <String>{};

  StreamSubscription<String>? _subscription;
  bool _busy = false;
  String? _message;

  /// Where the next scan goes. Session state, not a preference: you're either
  /// cataloguing your shelves or standing in a shop, and which one is obvious
  /// at the time.
  late bool _toWishlist = widget.initialWishlist;

  bool get _useCamera =>
      widget.cameraAvailable ??
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    final injected = widget.barcodes;
    if (injected != null) {
      _subscription = injected.listen(_onBarcode);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _manualIsbn.dispose();
    super.dispose();
  }

  Future<void> _onBarcode(String raw) async {
    final isbn13 = toIsbn13(raw);
    if (isbn13 == null) {
      // Not a book. Say so quietly and keep scanning — this is the common case
      // when a camera is pointed at anything else.
      if (mounted) setState(() => _message = 'That barcode isn’t a book (${raw.trim()})');
      return;
    }
    if (_seen.contains(isbn13)) return;
    if (_busy) return; // one lookup at a time; the next frame will re-offer it
    _seen.add(isbn13);
    await _add(isbn13);
  }

  Future<void> _add(String isbn13) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.repository.metadata.lookupByIsbn(isbn13);
      if (result == null) {
        if (!mounted) return;
        setState(() => _message =
            'No online match for ${formatIsbn13(isbn13)} — add it by hand?');
        return;
      }
      // Flag (don't block) a book that looks like one already here.
      final existing = await _duplicateOf(isbn13, result.title, result.authors);
      final wanted = _toWishlist;
      final bookId = wanted
          ? await widget.repository.wishlist.addFromSearch(result)
          : await widget.repository.addFromSearch(result);
      if (!mounted) return;
      setState(() {
        _added.insert(
          0,
          ScannedBook(
            bookId: bookId,
            isbn13: isbn13,
            title: result.title,
            duplicateOf: existing,
            wanted: wanted,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      // Offline, or the lookup failed: allow a retry of this exact barcode.
      _seen.remove(isbn13);
      setState(() => _message = 'Lookup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Title of an existing book matching this ISBN or title+author, via #15's
  /// classifier — one implementation of "is this the same book?" for both the
  /// folder import and the scanner.
  Future<String?> _duplicateOf(
    String isbn13,
    String title,
    List<String> authors,
  ) async {
    final db = widget.repository.db;
    // Live books only — scanning a book you trashed should add it back, not
    // flag it as a duplicate of something you can't see.
    final books = await (db.select(db.books)
          ..where((b) => b.deletedAt.isNull()))
        .get();
    final authorsByBook =
        await widget.repository.queries.watchAuthorsByBook().first;
    final library = [
      for (final b in books)
        LibraryFingerprint(
          bookId: b.id,
          title: b.title,
          isbn: b.isbn,
          authors: authorsByBook[b.id] ?? const [],
        ),
    ];
    // A synthetic "file name" carrying the scanned title and authors, so the
    // classifier's title+author arm applies without duplicating its rules here.
    final candidate = classify(
      path: '${authors.join(', ')} - $title.scan',
      sizeBytes: 0,
      format: 'scan',
      sha256: 'scan-$isbn13',
      library: library,
      isbn: isbn13,
    );
    return candidate.status == ImportStatus.newBook
        ? null
        : candidate.matchedTitle;
  }

  Future<void> _undo(ScannedBook book) async {
    final row = await widget.repository.watchBook(book.bookId).first;
    if (row != null) await widget.repository.deleteBook(row);
    if (!mounted) return;
    setState(() {
      _added.remove(book);
      _seen.remove(book.isbn13);
    });
  }

  Future<void> _submitManual() async {
    final isbn13 = toIsbn13(_manualIsbn.text);
    if (isbn13 == null) {
      setState(() => _message = 'That doesn’t look like an ISBN');
      return;
    }
    _manualIsbn.clear();
    _seen.add(isbn13);
    await _add(isbn13);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan books'),
        actions: [
          if (_added.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: Text('${_added.length} added')),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_useCamera)
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Only the symbologies books actually use, so the decoder
                  // isn't also hunting QR codes on the same frames.
                  BarcodeCamera(
                    formats: isbnFormats,
                    onCode: _onBarcode,
                    onError: (message) => _CameraUnavailable(detail: message),
                  ),
                  if (_busy)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('I own it'),
                  icon: Icon(Icons.library_add_check_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('I want it'),
                  icon: Icon(Icons.bookmark_add_outlined),
                ),
              ],
              selected: {_toWishlist},
              onSelectionChanged: (s) => setState(() => _toWishlist = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualIsbn,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'ISBN',
                      helperText: _useCamera
                          ? 'Or type it, if the barcode won’t scan'
                          : 'Type or paste an ISBN-10 or ISBN-13',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitManual(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _submitManual,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_message!)),
                ],
              ),
            ),
          Expanded(
            flex: 2,
            child: _added.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Point the camera at a book’s barcode, or type an ISBN. '
                        'Books you add appear here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _added.length,
                    itemBuilder: (context, i) {
                      final book = _added[i];
                      return ListTile(
                        leading: Icon(book.duplicateOf != null
                            ? Icons.copy_outlined
                            : book.wanted
                                ? Icons.bookmark_added_outlined
                                : Icons.check_circle_outline),
                        title: Text(book.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(book.duplicateOf != null
                            ? 'Possible duplicate of “${book.duplicateOf}”'
                            : book.wanted
                                ? '${formatIsbn13(book.isbn13)} · wishlist'
                                : formatIsbn13(book.isbn13)),
                        trailing: TextButton(
                          onPressed: () => _undo(book),
                          child: const Text('Undo'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.no_photography_outlined, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'No camera scanning here',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // The whole point of the fallback: say what happened, then point
                // at the field below rather than leaving a dead screen.
                Text('$detail\nYou can still type ISBNs below.',
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
