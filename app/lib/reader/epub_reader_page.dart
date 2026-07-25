import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
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
                child: HtmlWidget(chapter.html),
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
