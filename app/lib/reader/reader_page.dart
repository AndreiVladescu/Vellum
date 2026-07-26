import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'annotations/annotation_locator.dart';
import 'annotations/annotations_panel.dart';
import 'reader_settings.dart';
import 'reader_settings_sheet.dart';

/// The integrated PDF reader. Persists the current page as the user reads,
/// which drives the "Resume reading" state on the book's detail page, and lets
/// the reader leave bookmarks, highlights and notes (plan 5 #22).
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.book,
    required this.file,
    required this.repository,
  });

  final Book book;
  final File file;
  final LibraryRepository repository;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _controller = PdfViewerController();
  int? _page;
  int? _pageCount;

  AnnotationStore get _annotations => widget.repository.annotations;

  /// The live text selection, kept so the highlight action can ask it for the
  /// selected text and its page ranges. pdfrx hands this over on every selection
  /// change; it is not a snapshot, so it must not be used after a rebuild that
  /// clears the selection.
  PdfTextSelection? _selection;
  bool _hasSelection = false;

  /// Whether the current page already has a bookmark, so the action can toggle
  /// rather than stack duplicates. Refreshed on every page change.
  String? _bookmarkOnPage;

  /// Appearance settings (plan 5 #23).
  ReaderSettings? _settings;
  bool _chromeHidden = false;

  /// In-book text search. pdfrx does the work; this owns the query field's
  /// state and the match cursor.
  late final PdfTextSearcher _searcher = PdfTextSearcher(_controller)
    ..addListener(_onSearchChanged);
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    ReaderSettings.load().then((settings) {
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _chromeHidden = settings.immersive;
      });
      settings.addListener(_onSettingsChanged);
    });
  }

  @override
  void dispose() {
    _searcher.removeListener(_onSearchChanged);
    _searcher.dispose();
    _searchController.dispose();
    _settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _applyFit();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  /// Re-anchors the current page for the chosen fit. `topCenter` leaves a tall
  /// page free to scroll (fit width); `all` frames the whole page.
  void _applyFit() {
    final page = _page;
    if (page == null || !_controller.isReady) return;
    _controller.goToPage(
      pageNumber: page,
      anchor: _settings?.pdfFit == PdfFit.page
          ? PdfPageAnchor.all
          : PdfPageAnchor.topCenter,
    );
  }

  Future<void> _promptPageJump() async {
    final controller = TextEditingController();
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Go to page (1–${_pageCount ?? 1})'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (value) =>
              Navigator.pop(dialogContext, int.tryParse(value)),
          decoration: const InputDecoration(hintText: 'Page number'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    final count = _pageCount;
    if (target == null || count == null || !_controller.isReady) return;
    _controller.goToPage(pageNumber: target.clamp(1, count));
  }

  void _onPageChanged(int? page) {
    if (page == null || !_controller.isReady) return;
    setState(() {
      _page = page;
      _pageCount = _controller.pageCount;
    });
    // Fire-and-forget; tiny row update, safe to do per page turn.
    widget.repository.saveReadingPosition(
        widget.book.id, page, _controller.pageCount);
    _refreshBookmark(page);
  }

  Future<void> _refreshBookmark(int page) async {
    final existing = await _annotations.bookmarkAtPage(widget.book.id, page);
    if (!mounted) return;
    setState(() => _bookmarkOnPage = existing?.id);
  }

  Future<void> _toggleBookmark() async {
    final page = _page;
    if (page == null) return;
    final existing = _bookmarkOnPage;
    if (existing != null) {
      await _annotations.delete(existing);
      if (!mounted) return;
      setState(() => _bookmarkOnPage = null);
      return;
    }
    final id = await _annotations.add(
      bookId: widget.book.id,
      kind: AnnotationKind.bookmark,
      page: page,
      locator: PdfPageLocator(page: page),
    );
    if (!mounted) return;
    setState(() => _bookmarkOnPage = id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bookmarked page $page')),
    );
  }

  /// Turns the live selection into a highlight.
  ///
  /// The page and character range come from pdfrx's own extracted text, so a PDF
  /// highlight is objective — unlike the EPUB side, nothing here depends on this
  /// app's parsing. A selection spanning pages yields one annotation per page,
  /// because that is what the ranges describe and a single annotation would have
  /// to lie about where it is.
  Future<void> _highlightSelection({bool withNote = false}) async {
    final selection = _selection;
    if (selection == null || !selection.hasSelectedText) return;
    final ranges = await selection.getSelectedTextRanges();
    if (ranges.isEmpty || !mounted) return;

    String? note;
    if (withNote) {
      note = await _promptNote(ranges.first.text);
      if (note == null || !mounted) return; // cancelled
    }

    for (final range in ranges) {
      await _annotations.add(
        bookId: widget.book.id,
        kind: withNote ? AnnotationKind.note : AnnotationKind.highlight,
        page: range.pageNumber,
        locator: PdfTextLocator(
          page: range.pageNumber,
          start: range.start,
          end: range.end,
        ),
        quotedText: range.text,
        note: note,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(withNote
            ? 'Note saved'
            : 'Highlighted ${ranges.length == 1 ? 'passage' : '${ranges.length} passages'}'),
      ),
    );
  }

  Future<String?> _promptNote(String quote) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Note on this passage'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“${quote.length > 120 ? '${quote.substring(0, 120)}…' : quote}”',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'Your note'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return saved == true ? controller.text : null;
  }

  void _openPanel() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: AnnotationsPanel(
          book: widget.book,
          store: _annotations,
          onJump: (locator) {
            final page = switch (locator) {
              PdfPageLocator(:final page) => page,
              PdfTextLocator(:final page) => page,
              _ => null,
            };
            Navigator.of(context).pop();
            if (page != null && _controller.isReady) {
              _controller.goToPage(pageNumber: page);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final readerTheme = settings?.theme ?? ReaderTheme.light;
    return Scaffold(
      backgroundColor: readerTheme.background,
      appBar: _chromeHidden
          ? null
          : AppBar(
        backgroundColor: readerTheme.background,
        foregroundColor: readerTheme.foreground,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search in this book',
                  border: InputBorder.none,
                ),
                onSubmitted: (query) {
                  if (query.trim().isEmpty) return;
                  _searcher.startTextSearch(query.trim());
                },
              )
            : Text(widget.book.title),
        actions: [
          if (_searching) ...[
            if (_searcher.hasMatches)
              Center(
                child: Text(
                  '${(_searcher.currentIndex ?? 0) + 1}/${_searcher.matches.length}',
                ),
              ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous match',
              onPressed: _searcher.hasMatches ? _searcher.goToPrevMatch : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next match',
              onPressed: _searcher.hasMatches ? _searcher.goToNextMatch : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search',
              onPressed: () {
                _searcher.resetTextSearch();
                _searchController.clear();
                setState(() => _searching = false);
              },
            ),
          ],
          if (!_searching) ...[
          if (_page != null && _pageCount != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('$_page / $_pageCount'),
              ),
            ),
          // Selection-dependent actions appear only while text is selected, so
          // the bar isn't a row of buttons that silently do nothing.
          if (_hasSelection) ...[
            IconButton(
              icon: const Icon(Icons.format_color_text),
              tooltip: 'Highlight selection',
              onPressed: _highlightSelection,
            ),
            IconButton(
              icon: const Icon(Icons.sticky_note_2_outlined),
              tooltip: 'Note on selection',
              onPressed: () => _highlightSelection(withNote: true),
            ),
          ],
          IconButton(
            icon: Icon(_bookmarkOnPage == null
                ? Icons.bookmark_outline
                : Icons.bookmark),
            tooltip: _bookmarkOnPage == null
                ? 'Bookmark this page'
                : 'Remove bookmark',
            onPressed: _page == null ? null : _toggleBookmark,
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Annotations',
            onPressed: _openPanel,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search in this book',
            onPressed: () => setState(() => _searching = true),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (choice) {
              switch (choice) {
                case 'jump':
                  _promptPageJump();
                case 'options':
                  final s = _settings;
                  if (s != null) {
                    ReaderSettingsSheet.show(context, settings: s, pdf: true);
                  }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'jump', child: Text('Go to page…')),
              PopupMenuItem(value: 'options', child: Text('Reading options…')),
            ],
          ),
          ],
        ],
      ),
      body: GestureDetector(
        onTap: settings?.immersive == true
            ? () => setState(() => _chromeHidden = !_chromeHidden)
            : null,
        child: _nightModeWrap(
          enabled: settings?.pdfNightMode ?? false,
          child: PdfViewer.file(
        widget.file.path,
        controller: _controller,
        initialPageNumber: widget.book.lastReadPage ?? 1,
        params: PdfViewerParams(
          backgroundColor: readerTheme.background,
          onPageChanged: _onPageChanged,
          onViewerReady: (_, _) => _applyFit(),
          // Draws the search highlights pdfrx maintains for the active query.
          pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
          textSelectionParams: PdfTextSelectionParams(
            onTextSelectionChange: (selection) {
              _selection = selection;
              // Only rebuild when the *presence* of a selection changes: this
              // fires continuously while dragging.
              if (selection.hasSelectedText != _hasSelection && mounted) {
                setState(() => _hasSelection = selection.hasSelectedText);
              }
            },
          ),
        ),
      ),
        ),
      ),
    );
  }

  /// Applies the night-mode filter to a rendered page.
  ///
  /// A `ColorFiltered` wrap rather than a per-page paint: the pages are rasters,
  /// so the only way to darken them is to filter the pixels, and doing it once
  /// around the viewer keeps every page (and the gaps between them) consistent.
  Widget _nightModeWrap({required bool enabled, required Widget child}) =>
      enabled
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix(nightModeMatrix),
              child: child,
            )
          : child;
}
