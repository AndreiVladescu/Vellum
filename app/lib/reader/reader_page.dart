import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'annotations/annotation_locator.dart';
import 'annotations/annotations_panel.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
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
        ],
      ),
      body: PdfViewer.file(
        widget.file.path,
        controller: _controller,
        initialPageNumber: widget.book.lastReadPage ?? 1,
        params: PdfViewerParams(
          onPageChanged: _onPageChanged,
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
    );
  }
}
