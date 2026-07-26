import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'annotations/annotation_locator.dart';
import 'annotations/annotations_panel.dart';
import 'epub_book.dart';

/// The integrated EPUB reader: one chapter at a time, with previous/next
/// controls and a chapter list. The current chapter is persisted like a PDF
/// page, so "Resume reading" works the same for both formats.
class EpubReaderPage extends StatefulWidget {
  const EpubReaderPage({
    super.key,
    required this.book,
    required this.file,
    required this.repository,
  });

  final Book book;
  final File file;
  final LibraryRepository repository;

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  late final Future<EpubBook> _epub =
      EpubBook.openCached(widget.book.id, widget.file);
  final _scroll = ScrollController();
  int _chapter = 0; // set from the saved position once the book loads
  int _count = 0;
  bool _restored = false;
  Timer? _saveDebounce;

  AnnotationStore get _annotations => widget.repository.annotations;

  /// Reports the live text selection inside the chapter (plan 5 #22). The range
  /// it gives is in characters of the *rendered* chapter text, which is what
  /// makes an EPUB locator an approximation — see [_highlightSelection].
  final _selectionNotifier = SelectionListenerNotifier();
  ({int start, int end})? _selectionRange;

  /// Whether this chapter is bookmarked, so the action toggles instead of
  /// stacking. One bookmark per chapter: any finer and a long chapter collects
  /// noise, and the locator's scroll fraction still returns you to the spot.
  String? _bookmarkOnChapter;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _selectionNotifier.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _selectionNotifier.removeListener(_onSelectionChanged);
    _selectionNotifier.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!_selectionNotifier.registered) return;
    final range = _selectionNotifier.selection.range;
    final next = range == null
        ? null
        : (start: range.startOffset, end: range.endOffset);
    // Rebuild only when the presence of a selection changes; this fires
    // continuously while dragging.
    final had = _selectionRange != null;
    _selectionRange = next;
    if ((next != null) != had && mounted) setState(() {});
  }

  Future<void> _refreshBookmark() async {
    final existing =
        await _annotations.bookmarkAtChapter(widget.book.id, _chapter);
    if (!mounted) return;
    setState(() => _bookmarkOnChapter = existing?.id);
  }

  Future<void> _toggleBookmark() async {
    final existing = _bookmarkOnChapter;
    if (existing != null) {
      await _annotations.delete(existing);
      if (!mounted) return;
      setState(() => _bookmarkOnChapter = null);
      return;
    }
    final id = await _annotations.add(
      bookId: widget.book.id,
      kind: AnnotationKind.bookmark,
      chapter: _chapter,
      locator: EpubScrollLocator(chapter: _chapter, fraction: _scrollFraction),
    );
    if (!mounted) return;
    setState(() => _bookmarkOnChapter = id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bookmarked chapter ${_chapter + 1}')),
    );
  }

  /// Stores the current selection as a highlight (optionally with a note).
  ///
  /// **Honest about its own precision.** The offsets come from Flutter's
  /// selection, i.e. from the *rendered* chapter, while the quote is taken from
  /// this app's plain-text extraction of the same chapter; whitespace handling
  /// can make the two disagree by a few characters. That is exactly why the
  /// locator is versioned and why [resolveOffsets] treats the quote as
  /// authoritative and the offsets as a hint — a highlight that moves slightly
  /// beats one that confidently points at the wrong sentence.
  Future<void> _highlightSelection(EpubBook epub, {bool withNote = false}) async {
    final range = _selectionRange;
    if (range == null) return;
    final plain = epub.chapters[_chapter].plainText;
    final start = range.start.clamp(0, plain.length);
    final end = range.end.clamp(start, plain.length);
    final quote = plain.substring(start, end).trim();
    if (quote.isEmpty) return;

    String? note;
    if (withNote) {
      note = await _promptNote(quote);
      if (note == null || !mounted) return;
    }
    await _annotations.add(
      bookId: widget.book.id,
      kind: withNote ? AnnotationKind.note : AnnotationKind.highlight,
      chapter: _chapter,
      locator: EpubTextLocator(chapter: _chapter, start: start, end: end),
      quotedText: quote,
      note: note,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(withNote ? 'Note saved' : 'Highlighted')),
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

  void _openPanel(EpubBook epub) {
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
            final target = switch (locator) {
              EpubScrollLocator(:final chapter, :final fraction) =>
                (chapter: chapter, fraction: fraction),
              EpubTextLocator(:final chapter, :final start) => (
                  chapter: chapter,
                  // Approximate: scroll to where that character sits in the
                  // chapter's text. Good enough to land on the passage.
                  fraction: epub.chapters[chapter].plainText.isEmpty
                      ? 0.0
                      : start / epub.chapters[chapter].plainText.length,
                ),
              _ => null,
            };
            Navigator.of(context).pop();
            if (target == null) return;
            _goTo(target.chapter, epub.chapters.length);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scroll.hasClients) return;
              final max = _scroll.position.maxScrollExtent;
              if (max > 0) _scroll.jumpTo(target.fraction.clamp(0, 1) * max);
            });
          },
        ),
      ),
    );
  }

  double get _scrollFraction {
    if (!_scroll.hasClients) return 0;
    final max = _scroll.position.maxScrollExtent;
    return max <= 0 ? 0 : (_scroll.offset / max).clamp(0.0, 1.0);
  }

  // Persist the in-chapter scroll position, debounced so a flick isn't a write
  // storm. The chapter itself is saved eagerly on navigation in [_goTo].
  void _onScroll() {
    if (_count == 0) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      widget.repository.saveEpubPosition(
        widget.book.id,
        chapterIndex: _chapter,
        chapterCount: _count,
        scrollFraction: _scrollFraction,
      );
    });
  }

  void _goTo(int index, int count) {
    setState(() => _chapter = index.clamp(0, count - 1));
    _refreshBookmark();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // A new chapter starts at the top; save immediately (fraction 0).
    widget.repository.saveEpubPosition(
      widget.book.id,
      chapterIndex: _chapter,
      chapterCount: count,
      scrollFraction: 0,
    );
  }

  /// Restore the saved in-chapter scroll after the first layout: the global
  /// fraction minus the chapters below gives this chapter's fraction.
  void _restoreScroll(int count) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final global = (widget.book.readingProgress ?? 0) * count;
      final within = (global - _chapter).clamp(0.0, 1.0);
      final max = _scroll.position.maxScrollExtent;
      if (within > 0 && max > 0) _scroll.jumpTo(within * max);
    });
  }

  Future<void> _pickChapter(EpubBook epub) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView.builder(
        itemCount: epub.chapters.length,
        itemBuilder: (context, i) => ListTile(
          selected: i == _chapter,
          title: Text(epub.chapters[i].title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.pop(sheetContext, i),
        ),
      ),
    );
    if (picked != null && mounted) _goTo(picked, epub.chapters.length);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EpubBook>(
      future: _epub,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.book.title)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text("This EPUB couldn't be opened: ${snapshot.error}"),
              ),
            ),
          );
        }
        final epub = snapshot.data;
        if (epub == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.book.title)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final count = epub.chapters.length;
        _count = count;
        if (!_restored) {
          // Saved position is 1-based (like PDF pages); clamp for safety.
          _restored = true;
          _chapter = ((widget.book.lastReadPage ?? 1) - 1).clamp(0, count - 1);
          // Restore the in-chapter scroll once this chapter has laid out.
          _restoreScroll(count);
          _refreshBookmark();
        }
        final chapter = epub.chapters[_chapter];
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.book.title),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${_chapter + 1} / $count'),
                ),
              ),
              if (_selectionRange != null) ...[
                IconButton(
                  tooltip: 'Highlight selection',
                  icon: const Icon(Icons.format_color_text),
                  onPressed: () => _highlightSelection(epub),
                ),
                IconButton(
                  tooltip: 'Note on selection',
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  onPressed: () => _highlightSelection(epub, withNote: true),
                ),
              ],
              IconButton(
                tooltip: _bookmarkOnChapter == null
                    ? 'Bookmark this chapter'
                    : 'Remove bookmark',
                icon: Icon(_bookmarkOnChapter == null
                    ? Icons.bookmark_outline
                    : Icons.bookmark),
                onPressed: _toggleBookmark,
              ),
              IconButton(
                tooltip: 'Annotations',
                icon: const Icon(Icons.list_alt),
                onPressed: () => _openPanel(epub),
              ),
              IconButton(
                tooltip: 'Chapters',
                icon: const Icon(Icons.toc),
                onPressed: () => _pickChapter(epub),
              ),
            ],
          ),
          body: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(
              child: ConstrainedBox(
                // A comfortable measure on wide desktop windows.
                constraints: const BoxConstraints(maxWidth: 720),
                // Selectable so passages can be highlighted; the listener is
                // what turns a selection into character offsets (plan 5 #22).
                child: SelectionArea(
                  child: SelectionListener(
                    selectionNotifier: _selectionNotifier,
                    child: HtmlWidget(chapter.html),
                  ),
                ),
              ),
            ),
          ),
          // SafeArea(top:false) keeps the chapter controls above the Android
          // gesture/nav bar under edge-to-edge; the bar grows by that inset
          // rather than clipping, so no fixed height here.
          bottomNavigationBar: BottomAppBar(
            padding: EdgeInsets.zero,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous chapter',
                      onPressed:
                          _chapter > 0 ? () => _goTo(_chapter - 1, count) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        chapter.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next chapter',
                      onPressed: _chapter < count - 1
                          ? () => _goTo(_chapter + 1, count)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
