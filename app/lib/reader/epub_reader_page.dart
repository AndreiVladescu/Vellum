import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../shortcuts.dart';
import 'ai/ai_settings.dart';
import 'ai/ask_ai_sheet.dart';
import 'auto_scroll.dart';
import 'dictionary/dictionary_sheet.dart';
import 'dictionary/wordnet.dart';
import 'auto_scroll_bar.dart';
import 'annotations/annotation_locator.dart';
import 'annotations/annotations_panel.dart';
import 'annotations/epub_highlight_html.dart';
import 'annotations/highlight_palette.dart';
import 'night_mode.dart';
import 'edge_turn.dart';
import 'epub_book.dart';
import 'epub_search.dart';
import 'reader_hotkeys.dart';
import 'page_metric.dart';
import 'reader_settings.dart';
import 'translate/translate_sheet.dart';
import 'reader_settings_sheet.dart';

/// Where in a book a saved position points: a chapter and how far down it.
///
/// The saved form is one *global* fraction across the whole book plus the 1-based
/// chapter in `lastReadPage`. Converting between the two is the whole of plan 4
/// §E15 (in-chapter scroll restore) and easy to get subtly wrong, so it lives
/// here as two pure functions rather than inline in a post-frame callback.
({int chapter, double fraction}) epubPositionFrom({
  required double? progress,
  required int? lastReadPage,
  required int chapterCount,
}) {
  if (chapterCount <= 0) return (chapter: 0, fraction: 0);
  final chapter = ((lastReadPage ?? 1) - 1).clamp(0, chapterCount - 1);
  final global = (progress ?? 0) * chapterCount;
  // The chapter index is authoritative (it was saved explicitly); the fraction
  // is whatever is left over inside it.
  final within = (global - chapter).clamp(0.0, 1.0);
  return (chapter: chapter, fraction: within.toDouble());
}

/// The inverse: the global fraction to store for a position inside a chapter.
double epubGlobalProgress({
  required int chapter,
  required int chapterCount,
  required double fraction,
}) {
  if (chapterCount <= 0) return 0;
  return ((chapter + fraction.clamp(0, 1)) / chapterCount).clamp(0, 1).toDouble();
}

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

class _EpubReaderPageState extends State<EpubReaderPage>
    with SingleTickerProviderStateMixin {
  late final Future<EpubBook> _epub =
      EpubBook.openCached(widget.book.id, widget.file);
  final _scroll = ScrollController();
  int _chapter = 0; // set from the saved position once the book loads
  int _count = 0;
  bool _restored = false;
  Timer? _saveDebounce;

  AnnotationStore get _annotations => widget.repository.annotations;

  /// Records this sitting (plan 5 #19). Pages are chapters here, which is the
  /// honest unit for an EPUB — the stats say "pages" because that is what the
  /// reader turns.
  late final SessionRecorder _session =
      SessionRecorder(widget.repository.db);

  /// Appearance settings (plan 5 #23). Loaded here rather than passed in, so a
  /// reader opened from anywhere gets them without every call site threading
  /// them through.
  ReaderSettings? _settings;

  /// Whether the chrome is currently hidden; seeded from the preference so a tap
  /// can reveal it temporarily without changing the setting.
  bool _chromeHidden = false;

  /// Enters or leaves reading mode: the chrome gone, and the screen kept awake.
  ///
  /// The same thing the PDF reader does, and for the same reason — reading is
  /// the one thing you do with a phone without touching it, so a screen that
  /// dims halfway down a chapter is why people tap at nothing.
  Future<void> _setReadingMode(bool on) async {
    setState(() => _chromeHidden = on);
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // A platform without a wakelock, or one that refuses: reading mode is
      // still reading mode without it.
    }
  }

  /// The self-scroller. Lines a minute here rather than pages: an EPUB has no
  /// pages, and a line is a thing the settings know the exact height of —
  /// `fontSize × lineHeight`. See `auto_scroll.dart`.
  Ticker? _autoTicker;
  Duration _autoLastTick = Duration.zero;
  bool _autoHeld = false;
  int _autoStuckFrames = 0;

  bool get _autoScrolling => _autoTicker?.isActive ?? false;

  double get _autoSpeed => clampAutoScrollSpeed(
        _settings?.autoScrollLinesPerMinute ?? defaultAutoScrollLinesPerMinute,
        min: minAutoScrollLinesPerMinute,
        max: maxAutoScrollLinesPerMinute,
      );

  /// One line of body text as it is drawn right now.
  double get _lineHeightOnScreen {
    final settings = _settings;
    if (settings == null) return 0;
    return settings.fontSize * settings.lineHeight;
  }

  void _toggleAutoScroll() {
    if (_autoScrolling) {
      _stopAutoScroll();
    } else {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    if (!_scroll.hasClients) return;
    _autoHeld = false;
    _autoStuckFrames = 0;
    _autoLastTick = Duration.zero;
    _autoTicker ??= createTicker(_onAutoTick);
    _autoTicker!.start();
    setState(() {});
  }

  void _stopAutoScroll() {
    _autoTicker?.stop();
    if (mounted) setState(() {});
  }

  void _onAutoTick(Duration elapsed) {
    final seconds = (elapsed - _autoLastTick).inMicroseconds /
        Duration.microsecondsPerSecond;
    _autoLastTick = elapsed;
    // A long gap means the app was away; skip it rather than lurching.
    if (_autoHeld || seconds <= 0 || seconds > 0.5 || !_scroll.hasClients) {
      return;
    }
    final speed = autoScrollPixelsPerSecond(
      unitsPerMinute: _autoSpeed,
      unitHeightPixels: _lineHeightOnScreen,
    );
    if (speed <= 0) return;
    final position = _scroll.position;
    final before = position.pixels;
    final target =
        (before + speed * seconds).clamp(0.0, position.maxScrollExtent);
    _scroll.jumpTo(target);
    if ((target - before).abs() < 0.05) {
      // The bottom of the chapter. Roll into the next one rather than stopping
      // dead at every chapter break — the same reasoning as [_pageForward].
      if (++_autoStuckFrames >= autoScrollStuckFrames) {
        if (_chapter < _count - 1) {
          _autoStuckFrames = 0;
          _goTo(_chapter + 1, _count);
        } else {
          _stopAutoScroll();
        }
      }
    } else {
      _autoStuckFrames = 0;
    }
  }

  Future<void> _setAutoSpeed(double linesPerMinute) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setAutoScrollLinesPerMinute(roundAutoScrollSpeed(
      clampAutoScrollSpeed(
        linesPerMinute,
        min: minAutoScrollLinesPerMinute,
        max: maxAutoScrollLinesPerMinute,
      ),
    ));
  }

  /// Reports the live text selection inside the chapter (plan 5 #22). The range
  /// it gives is in characters of the *rendered* chapter text, which is what
  /// makes an EPUB locator an approximation — see [_highlightSelection].
  final _selectionNotifier = SelectionListenerNotifier();
  ({int start, int end})? _selectionRange;

  /// Whether this chapter is bookmarked, so the action toggles instead of
  /// stacking. One bookmark per chapter: any finer and a long chapter collects
  /// noise, and the locator's scroll fraction still returns you to the spot.
  String? _bookmarkOnChapter;

  /// This book's annotations, so the chapter markup can carry its highlights.
  List<Annotation> _bookAnnotations = const [];
  StreamSubscription<List<Annotation>>? _annotationsSub;

  /// The parsed book, once the future has resolved — so the shortcuts, which
  /// live outside the FutureBuilder, can reach the text they search.
  EpubBook? _loaded;

  /// In-book search. Unlike the PDF side there is no package to hand this to,
  /// so [searchEpub] does it over the chapters' plain text.
  bool _searching = false;
  final _searchController = TextEditingController();
  List<EpubSearchHit> _hits = const [];
  bool _hitsTruncated = false;
  int _hitIndex = 0;

  /// Ctrl+F / Ctrl+G, which have to work before the page is clicked.
  late final ReaderHotkeys _hotkeys = ReaderHotkeys(
    isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
    onFind: _openSearch,
    onGoTo: _promptChapterJump,
    onEscape: () {
      if (!_searching) return false;
      _closeSearch();
      return true;
    },
  );

  @override
  void initState() {
    super.initState();
    _hotkeys.attach();
    _annotationsSub =
        _annotations.watchForBook(widget.book.id).listen((annotations) {
      if (mounted) setState(() => _bookAnnotations = annotations);
    });
    _scroll.addListener(_onScroll);
    _selectionNotifier.addListener(_onSelectionChanged);
    ReaderSettings.load().then((settings) {
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _chromeHidden = settings.immersive;
      });
      settings.addListener(_onSettingsChanged);
    });
    _session.begin(widget.book.id, page: (widget.book.lastReadPage ?? 1));
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _autoTicker?.dispose();
    // The wakelock belongs to this page, not to the app.
    unawaited(WakelockPlus.disable().catchError((_) {}));
    _hotkeys.detach();
    _annotationsSub?.cancel();
    _saveDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _selectionNotifier.removeListener(_onSelectionChanged);
    _selectionNotifier.dispose();
    _settings?.removeListener(_onSettingsChanged);
    _searchController.dispose();
    _session.end(page: _chapter + 1);
    _scroll.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!_selectionNotifier.registered) return;
    final range = _selectionNotifier.selection.range;
    final next = range == null
        ? null
        : (start: range.startOffset, end: range.endOffset);
    // Rebuild only when something the toolbar shows changes; this fires
    // continuously while dragging. Two things do: whether there is a selection
    // at all, and whether it is a single word — which is what decides if the
    // dictionary button is there. Without the second test, narrowing a phrase
    // down to one word never brings the button back.
    final had = _selectionRange != null;
    final hadWord = _selectionIsWord;
    _selectionRange = next;
    // Selecting text is asking for the toolbar — highlight, note, look up,
    // translate all live there. Only on the edge where a selection appears.
    if (!had && next != null && _chromeHidden && mounted) {
      _setReadingMode(false);
    }
    if (((next != null) != had || _selectionIsWord != hadWord) && mounted) {
      setState(() {});
    }
  }

  /// Whether what is selected right now is one word — see [singleWord].
  bool get _selectionIsWord {
    final epub = _loaded;
    if (epub == null || _selectionRange == null) return false;
    return singleWord(_selectedText(epub)) != null;
  }

  /// The marker currently in hand. A setting, not a question asked per
  /// highlight — see [HighlightColorButton].
  HighlightColor get _highlightColour =>
      HighlightColor.fromArgb(_settings?.highlightColor);

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
    if (quote.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select some text first.')));
      return;
    }

    final colour = _highlightColour;

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
      color: colour.argb,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(withNote ? 'Note saved' : 'Highlighted')),
    );
  }

  /// The selected text, as the chapter's own plain text has it.
  String _selectedText(EpubBook epub) {
    final range = _selectionRange;
    if (range == null) return '';
    final plain = epub.chapters[_chapter].plainText;
    final start = range.start.clamp(0, plain.length);
    final end = range.end.clamp(start, plain.length);
    return plain.substring(start, end).trim();
  }

  /// Looks the selected word up. Words only, as asked — see [singleWord].
  Future<void> _defineSelection(EpubBook epub) async {
    final range = _selectionRange;
    if (range == null) return;
    final word = singleWord(_selectedText(epub));
    if (word == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select a single word to look it up.'),
      ));
      return;
    }
    final plain = epub.chapters[_chapter].plainText;
    final start = range.start.clamp(0, plain.length);
    final end = range.end.clamp(start, plain.length);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DictionarySheet(
        word: word,
        onSaveAsNote: (definition) => _annotations.add(
          bookId: widget.book.id,
          kind: AnnotationKind.note,
          chapter: _chapter,
          locator: EpubTextLocator(chapter: _chapter, start: start, end: end),
          quotedText: word,
          note: definition,
          color: _highlightColour.argb,
        ),
      ),
    );
  }

  /// The model's settings, loaded the first time something asks for them.
  AiSettings? _ai;

  Future<AiSettings> _aiSettings() async => _ai ??= await AiSettings.load();

  /// Sends the selection — or the whole chapter — to whatever model has been
  /// named. The chapter as a fallback for the same reason the PDF reader sends
  /// the page: the question "what is this about" comes before the reading.
  Future<void> _askAi(EpubBook epub, {bool wholeChapter = false}) async {
    final range = _selectionRange;
    final plain = epub.chapters[_chapter].plainText;
    final selected = wholeChapter ? '' : _selectedText(epub);
    final passage = selected.isEmpty ? plain.trim() : selected;
    final what = selected.isEmpty ? 'chapter' : 'passage';
    if (passage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There is no text here to send.')),
      );
      return;
    }
    final settings = await _aiSettings();
    if (!mounted) return;
    final start = range == null ? 0 : range.start.clamp(0, plain.length);
    final end = range == null ? 0 : range.end.clamp(start, plain.length);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AskAiSheet(
        passage: passage,
        settings: settings,
        bookTitle: widget.book.title,
        what: what,
        onSaveAsNote: (answer) => _annotations.add(
          bookId: widget.book.id,
          kind: AnnotationKind.note,
          chapter: _chapter,
          locator: selected.isEmpty
              ? EpubScrollLocator(chapter: _chapter, fraction: 0)
              : EpubTextLocator(chapter: _chapter, start: start, end: end),
          quotedText: selected.isEmpty ? null : selected,
          note: answer,
          color: _highlightColour.argb,
        ),
      ),
    );
  }

  /// Translates the selected passage. Mirrors the PDF reader's version, down
  /// to keeping the result as a note on the passage — the two readers do the
  /// same things in the same order, and this is one of them.
  Future<void> _translateSelection(EpubBook epub) async {
    final settings = _settings;
    final range = _selectionRange;
    if (settings == null || range == null) return;
    final plain = epub.chapters[_chapter].plainText;
    final start = range.start.clamp(0, plain.length);
    final end = range.end.clamp(start, plain.length);
    final quote = plain.substring(start, end).trim();
    if (quote.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select some text first.')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TranslateSheet(
        passage: quote,
        settings: settings,

        onSaveAsNote: (translation) => _annotations.add(
          bookId: widget.book.id,
          kind: AnnotationKind.note,
          chapter: _chapter,
          locator: EpubTextLocator(chapter: _chapter, start: start, end: end),
          quotedText: quote,
          note: translation,
          color: _highlightColour.argb,
        ),
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

  void _openSearch() {
    if (_searching || _loaded == null) return;
    setState(() => _searching = true);
  }

  void _closeSearch() {
    if (!_searching) return;
    _searchController.clear();
    setState(() {
      _searching = false;
      _hits = const [];
      _hitsTruncated = false;
      _hitIndex = 0;
    });
  }

  /// Runs the query and jumps to the first hit.
  ///
  /// On submit rather than on every keystroke: `plainText` re-extracts each
  /// chapter from its markup, so searching a long book is work worth doing once
  /// per question rather than once per letter.
  void _runSearch(String query) {
    final epub = _loaded;
    if (epub == null) return;
    final result = searchEpub(epub.chapters, query);
    setState(() {
      _hits = result.hits;
      _hitsTruncated = result.truncated;
      _hitIndex = 0;
    });
    if (_hits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No match for “${query.trim()}”')),
      );
      return;
    }
    _goToHit(0);
  }

  void _stepHit(int by) {
    if (_hits.isEmpty) return;
    // Wraps, like every find bar: the match after the last one is the first.
    final next = (_hitIndex + by) % _hits.length;
    setState(() => _hitIndex = next < 0 ? next + _hits.length : next);
    _goToHit(_hitIndex);
  }

  void _goToHit(int index) {
    final epub = _loaded;
    if (epub == null || index < 0 || index >= _hits.length) return;
    final hit = _hits[index];
    _goTo(hit.chapter, epub.chapters.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) _scroll.jumpTo(hit.fraction.clamp(0, 1) * max);
    });
  }

  /// Go to chapter N. Chapters are what this reader turns, and what the saved
  /// position counts, so they are the unit the box asks for.
  Future<void> _promptChapterJump() async {
    final count = _count;
    if (count <= 0) return; // the book hasn't opened yet
    final controller = TextEditingController();
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Go to chapter (1–$count)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (value) =>
              Navigator.pop(dialogContext, int.tryParse(value)),
          decoration: const InputDecoration(hintText: 'Chapter number'),
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
    if (target == null || !mounted) return;
    _goTo(target.clamp(1, count) - 1, count);
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

  /// One screenful forward, rolling into the next chapter at the end.
  ///
  /// The unit people mean by "page" here is a screenful, not a chapter: tapping
  /// the right edge repeatedly should walk through the book, and stopping dead
  /// at the bottom of every chapter would make the gesture useless exactly
  /// where it is most wanted.
  void _pageForward(int count) {
    if (_scroll.hasClients) {
      final position = _scroll.position;
      // A little overlap, so the line you were reading is still on screen —
      // an exact viewport jump loses the sentence that straddles the fold.
      final step = position.viewportDimension * 0.86;
      if (position.pixels < position.maxScrollExtent - 4) {
        _scroll.animateTo(
          (position.pixels + step).clamp(0.0, position.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      }
    }
    if (_chapter < count - 1) _goTo(_chapter + 1, count);
  }

  /// One screenful back, rolling into the previous chapter's *end*.
  void _pageBack(int count) {
    if (_scroll.hasClients) {
      final position = _scroll.position;
      final step = position.viewportDimension * 0.86;
      if (position.pixels > 4) {
        _scroll.animateTo(
          (position.pixels - step).clamp(0.0, position.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      }
    }
    if (_chapter > 0) {
      _goTo(_chapter - 1, count);
      // Land at the bottom of the previous chapter — going "back" to its first
      // line would skip everything you were about to re-read.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  void _goTo(int index, int count) {
    setState(() => _chapter = index.clamp(0, count - 1));
    _session.touch(page: _chapter + 1);
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
      final target = epubPositionFrom(
        progress: widget.book.readingProgress,
        lastReadPage: widget.book.lastReadPage,
        chapterCount: count,
      );
      final max = _scroll.position.maxScrollExtent;
      if (target.fraction > 0 && max > 0) {
        _scroll.jumpTo(target.fraction * max);
      }
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
        _loaded = epub;
        if (!_restored) {
          // Saved position is 1-based (like PDF pages); clamp for safety.
          _restored = true;
          _chapter = epubPositionFrom(
            progress: widget.book.readingProgress,
            lastReadPage: widget.book.lastReadPage,
            chapterCount: count,
          ).chapter;
          // Restore the in-chapter scroll once this chapter has laid out.
          _restoreScroll(count);
          _refreshBookmark();
        }
        final chapter = epub.chapters[_chapter];
        final settings = _settings;
        final dark = settings?.nightMode ?? false;
        final readerTheme = settings?.effectiveTheme ?? ReaderTheme.light;
        // Asked of the page rather than of the switch. They amount to the same
        // thing now that Dark is not a page colour, but the rule that matters
        // is "the paper is dark, so the book's own near-black type has to go" —
        // and that stays true whatever a future palette does.
        final darkPage = readerTheme.isDark;
        return Scaffold(
          backgroundColor: readerTheme.background,
          // Immersive mode drops the bar entirely rather than fading it: a
          // translucent bar over prose is still something to read around.
          appBar: _chromeHidden
              ? null
              : AppBar(
            backgroundColor: readerTheme.background,
            foregroundColor: readerTheme.foreground,
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(color: readerTheme.foreground),
                    decoration: const InputDecoration(
                      hintText: 'Search in this book',
                      border: InputBorder.none,
                    ),
                    onSubmitted: _runSearch,
                  )
                : Text(widget.book.title),
            actions: [
              if (_searching) ...[
                if (_hits.isNotEmpty)
                  Center(
                    child: Text('${_hitIndex + 1}/${_hits.length}'
                        '${_hitsTruncated ? '+' : ''}'),
                  ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Previous match',
                  onPressed: _hits.isEmpty ? null : () => _stepHit(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Next match',
                  onPressed: _hits.isEmpty ? null : () => _stepHit(1),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close search (Esc)',
                  onPressed: _closeSearch,
                ),
              ],
              if (!_searching) ...[
              // The counter is the obvious place to press when you want a
              // particular chapter, so it is the control rather than a label.
              // Hold it to change what it counts, exactly as in the PDF
              // reader. An EPUB counts chapters rather than pages, so *time
              // left* has nothing to measure and is left out of the cycle here.
              GestureDetector(
                onLongPress: () {
                  final s = _settings;
                  if (s == null) return;
                  var next = s.pageMetric.next;
                  if (next == PageMetric.timeLeft) next = next.next;
                  s.setPageMetric(next);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(next.label),
                      duration: const Duration(milliseconds: 900),
                    ),
                  );
                },
                child: TextButton(
                  onPressed: _promptChapterJump,
                  style: TextButton.styleFrom(
                    foregroundColor: readerTheme.foreground,
                  ),
                  child: Text(pageMetricLabel(
                    settings?.pageMetric ?? PageMetric.pagesOf,
                    page: _chapter + 1,
                    count: count,
                  )),
                ),
              ),
              if (_selectionRange != null) ...[
                IconButton(
                  tooltip: 'Highlight in ${_highlightColour.label}',
                  icon: Icon(Icons.format_color_text,
                      color: _highlightColour.color),
                  onPressed: () => _highlightSelection(epub),
                ),
                if (settings != null)
                  HighlightColorButton(
                    selected: _highlightColour,
                    onChanged: (colour) =>
                        settings.setHighlightColor(colour.argb),
                  ),
                IconButton(
                  tooltip: 'Note on selection',
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  onPressed: () => _highlightSelection(epub, withNote: true),
                ),
                // A word, not a phrase — the same rule as the PDF reader.
                if (_selectionIsWord)
                  IconButton(
                    tooltip: 'Look up “${singleWord(_selectedText(epub))}”',
                    icon: const Icon(Icons.menu_book_outlined),
                    onPressed: () => _defineSelection(epub),
                  ),
                IconButton(
                  tooltip: 'Ask a model about this',
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: () => _askAi(epub),
                ),
                // Same as the PDF reader: always offered, because the sheet is
                // where it gets set up.
                if (settings != null)
                  IconButton(
                    tooltip: 'Translate selection',
                    icon: const Icon(Icons.translate),
                    onPressed: () => _translateSelection(epub),
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
                icon: Icon(_autoScrolling
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline),
                tooltip: _autoScrolling
                    ? 'Stop scrolling by itself'
                    : 'Scroll by itself',
                onPressed: _toggleAutoScroll,
              ),
              IconButton(
                icon: const Icon(Icons.fullscreen),
                tooltip: 'Reading mode — swipe down from the top to come back',
                onPressed: () => _setReadingMode(true),
              ),
              IconButton(
                tooltip: 'Annotations',
                icon: const Icon(Icons.list_alt),
                onPressed: () => _openPanel(epub),
              ),
              IconButton(
                tooltip: 'Search in this book (${commandModifierLabel()}F)',
                icon: const Icon(Icons.search),
                onPressed: _openSearch,
              ),
              IconButton(
                tooltip: 'Chapters',
                icon: const Icon(Icons.toc),
                onPressed: () => _pickChapter(epub),
              ),
              // The whole chapter, for when nothing is selected — the reader's
              // "what is this one about" before reading it.
              IconButton(
                tooltip: 'Ask a model about this chapter',
                icon: const Icon(Icons.auto_awesome),
                onPressed: () => _askAi(epub, wholeChapter: true),
              ),
              if (settings != null)
                IconButton(
                  tooltip: 'Reading options',
                  icon: const Icon(Icons.text_fields),
                  onPressed: () => ReaderSettingsSheet.show(
                    context,
                    settings: settings,
                    typography: true,
                  ),
                ),
              ],
            ],
          ),
          body: LayoutBuilder(builder: (context, constraints) {
            final strip = ReaderEdgeTurn.stripWidth(
              constraints.maxWidth,
              settings?.measure ?? 720,
            );
            return Stack(children: [
              Listener(
                // Holds the self-scroller still while a finger is down, rather
                // than stopping it: steadying the page is not the same as
                // wanting to stop. A raw Listener observes without joining the
                // gesture arena, so the scroll view keeps its own drags.
                onPointerDown: (_) => _autoHeld = _autoScrolling,
                onPointerUp: (_) => _autoHeld = false,
                onPointerCancel: (_) => _autoHeld = false,
                child: GestureDetector(
            // A tap toggles the chrome when the reader asked for a
            // distraction-free page; otherwise it does nothing, so a stray tap
            // can't hide the controls someone is using.
            onTap: settings?.immersive == true
                ? () => _setReadingMode(!_chromeHidden)
                : null,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    // The measure: a full-width line on a wide monitor is
                    // unreadable however good the type is (plan 5 #23).
                    constraints: BoxConstraints(
                      maxWidth: settings?.measure ?? 720,
                    ),
                    // Selectable so passages can be highlighted; the listener is
                    // what turns a selection into character offsets (plan 5 #22).
                    child: SelectionArea(
                      child: SelectionListener(
                        selectionNotifier: _selectionNotifier,
                        child: HtmlWidget(
                          // Stored highlights painted into the markup, so the
                          // text is coloured like a marker rather than only
                          // listed in the panel.
                          withHighlights(
                            // Night mode: the book's own colours come out
                            // first, or a heading that asked for near-black
                            // stays near-black on a near-black page.
                            darkPage
                                ? withoutBookColours(chapter.html)
                                : chapter.html,
                            _bookAnnotations,
                            _chapter,
                            ink: readerTheme.foreground,
                          ),
                          // The reader's own typography, applied to the book's
                          // text only — the surrounding UI keeps following the
                          // system text scale.
                          textStyle: settings?.bodyTextStyle() ??
                              TextStyle(color: readerTheme.foreground),
                          // Night mode: the book's own colours would otherwise
                          // win — a stylesheet saying `color: #222` is black
                          // text on a black page. Its *pictures* are handled by
                          // the factory, which greys them.
                          customStylesBuilder: darkPage
                              ? (element) => element.localName == 'mark'
                                  ? null
                                  : {'color': cssHex(readerTheme.foreground)}
                              : null,
                          factoryBuilder: dark ? NightModeFactory.new : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
              ),
              // A swipe down from the very top edge brings the chrome back, the
              // way a video player does — a deliberate gesture from a strip
              // nothing else uses, because taps are how pages turn.
              if (_chromeHidden)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 48,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity != null &&
                          details.primaryVelocity! > 0) {
                        _setReadingMode(false);
                      }
                    },
                  ),
                ),
              // What the bottom bar would have said, now that it is gone.
              // Chapters rather than pages: that is what this reader turns,
              // and calling them pages would be a number nobody could check.
              if (_chromeHidden)
                Positioned(
                  left: 16,
                  bottom: 12,
                  child: IgnorePointer(
                    child: Text(
                      readingModeStatus(
                        page: _chapter + 1,
                        count: count,
                        unit: 'chapter',
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: readerTheme.foreground.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              // The speed control, shown only while the page is moving by
              // itself — and shown in reading mode too, because that is where
              // it is used.
              if (_autoScrolling)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: AutoScrollBar(
                      speed: _autoSpeed,
                      unit: 'lines',
                      min: minAutoScrollLinesPerMinute,
                      max: maxAutoScrollLinesPerMinute,
                      onSpeed: _setAutoSpeed,
                      onStop: _stopAutoScroll,
                    ),
                  ),
                ),
              // The edge tap zones. The chevron sits at the vertical middle of
              // the page — where your thumb already is — and the whole strip is
              // the target, not just the glyph.
              ReaderEdgeTurn(
                width: strip,
                alignment: Alignment.centerLeft,
                icon: Icons.chevron_left,
                tooltip: 'Back a page',
                colour: readerTheme.foreground,
                onTap: () => _pageBack(count),
              ),
              ReaderEdgeTurn(
                width: strip,
                alignment: Alignment.centerRight,
                icon: Icons.chevron_right,
                tooltip: 'Forward a page',
                colour: readerTheme.foreground,
                onTap: () => _pageForward(count),
              ),
            ]);
          }),
          // Just the chapter's name now: the corner chevrons that used to sit
          // either side of it did what the page edges do, and two controls for
          // one action is one too many. Jumping to a *particular* chapter is
          // still the Chapters button, which is the thing they were worse at.
          //
          // SafeArea(top:false) keeps it above the Android gesture/nav bar under
          // edge-to-edge; the bar grows by that inset rather than clipping.
          bottomNavigationBar: _chromeHidden
              ? null
              : BottomAppBar(
            color: readerTheme.background,
            padding: EdgeInsets.zero,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      chapter.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The bar takes the reader's page colour, so its text has
                      // to take the reader's ink — the app theme's would be
                      // dark-on-dark here.
                      style: TextStyle(color: readerTheme.foreground),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
