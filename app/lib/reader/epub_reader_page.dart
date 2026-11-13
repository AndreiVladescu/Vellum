import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout, kTouchSlop;
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
import 'chapter_markup.dart';
import 'epub_book.dart';
import 'epub_pagination.dart';
import 'paged_chapter.dart';
import 'reader_gestures.dart';
import 'epub_search.dart';
import 'reader_hotkeys.dart';
import 'reader_search_field.dart';
import 'page_metric.dart';
import 'reader_actions.dart';
import 'reader_settings.dart';
import 'translate/translate_sheet.dart';
import 'reader_settings_sheet.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/labels.dart';

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
    this.bookFile,
    this.initialChapter,
    required this.repository,
  });

  final Book book;
  final File file;

  /// The library row behind [file] — see [ReaderPage.bookFile].
  final BookFile? bookFile;

  /// Open here rather than where this file was left off — how an accepted
  /// carry-over from the book's *other* file arrives (see `ReadButton`). The
  /// saved position is left alone until the reader records a new one.
  final int? initialChapter;
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

  /// Paged mode (roadmap v1.4.0): where in the chapter the page is, and the
  /// chapter cut into pages, once it has been laid out. The anchor is the
  /// position; the page number is derived from it against [_pages], so a
  /// re-pagination (text size, window size) keeps the place.
  PageAnchor _anchor = const AtScrollFraction(0);
  ChapterPages? _pages;

  /// The layout last built, to notice the preference changing under us.
  EpubLayout? _layout;

  bool get _paged => _settings?.epubLayout == EpubLayout.paged;

  /// Where a pointer went down, for telling a tap from a swipe from a
  /// selection — see [_onPointerDown].
  ({Offset at, Duration time, PointerDeviceKind kind})? _pointerStart;

  /// So a swipe can drop the selection its drag made on the way.
  final _selectionArea = GlobalKey<SelectionAreaState>();

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
    // Judged against what this tick asked for, not a fixed pixel amount — see
    // autoScrollFrameStuck. At the slowest speed a tick can legitimately move
    // under a twentieth of a pixel, which a fixed threshold mistook for the
    // bottom of the chapter.
    if (autoScrollFrameStuck(attempted: speed * seconds, actual: (target - before).abs())) {
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
  /// Always replaced, never changed in place: [ChapterMarkup] keys on it.
  List<Annotation> _bookAnnotations = const [];

  /// The chapter as the `HtmlWidget` shows it, remade only when its inputs
  /// change rather than on every rebuild (performance round #9).
  final _markup = ChapterMarkup();
  StreamSubscription<List<Annotation>>? _annotationsSub;

  /// The parsed book, once the future has resolved — so the shortcuts, which
  /// live outside the FutureBuilder, can reach the text they search.
  EpubBook? _loaded;

  /// In-book search. Unlike the PDF side there is no package to hand this to,
  /// so [searchEpub] does it over the chapters' plain text.
  bool _searching = false;
  final _searchController = TextEditingController();

  /// Owned here so Ctrl+F can focus the box explicitly: `autofocus` does
  /// nothing once something else in the scope has focus, which is the case as
  /// soon as the page has been clicked.
  final _searchFocus = FocusNode();
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
    isPaged: () => _paged,
    onPageStep: (delta) =>
        delta > 0 ? _pageForward(_count) : _pageBack(_count),
    onNudge: _nudge,
    spaceTurnsPages: true,
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
        _layout = settings.epubLayout;
        _chromeHidden = settings.immersive;
      });
      settings.addListener(_onSettingsChanged);
    });
    _session.begin(widget.book.id, page: (widget.book.lastReadPage ?? 1));
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final layout = _settings?.epubLayout;
    if (layout != _layout) _switchLayout(layout);
    setState(() {});
  }

  /// Keeps the place across a switch between scrolled and paged: both speak
  /// the same scroll fraction, which is also what is saved.
  void _switchLayout(EpubLayout? layout) {
    _layout = layout;
    if (layout == EpubLayout.paged) {
      if (_autoScrolling) _stopAutoScroll();
      if (_scroll.hasClients) _anchor = AtScrollFraction(_scrollFraction);
      _pages = null;
    } else {
      final fraction = _pagedFraction;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(fraction * _scroll.position.maxScrollExtent);
      });
    }
  }

  /// The paged position as a scroll fraction — what gets saved.
  double get _pagedFraction {
    final pages = _pages;
    if (pages != null && pages.ready) {
      return pages.scrollFractionOf(pages.pageFor(_anchor));
    }
    return switch (_anchor) {
      AtScrollFraction(:final fraction) => fraction,
      // Not laid out yet, so no better answer than the proportion itself.
      AtContentFraction(:final fraction) => fraction,
    };
  }

  /// Where in the chapter the reader is, whichever way it is showing it.
  double get _positionFraction => _paged ? _pagedFraction : _scrollFraction;

  int get _pageInChapter => _pages?.pageFor(_anchor) ?? 0;

  void _onPaginated(ChapterPages pages) {
    if (!mounted) return;
    setState(() => _pages = pages);
  }

  /// A few lines' worth of scrolling — the arrow keys in scrolled mode.
  void _nudge(int delta) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final step = (_lineHeightOnScreen > 0 ? _lineHeightOnScreen : 24) * 3;
    _scroll.jumpTo(
        (position.pixels + delta * step).clamp(0.0, position.maxScrollExtent));
  }

  /// Paged mode's taps and swipes, read from raw pointer events.
  ///
  /// **Why not a GestureDetector.** The chapter is selectable, and its
  /// selection recogniser sits deeper in the tree, so it wins every tap and —
  /// on touch — every horizontal drag (dragging sideways selects text). A
  /// [Listener] sees the pointer whatever wins. Nothing is turned if something
  /// was already selected when the pointer went down: that tap is dismissing
  /// the selection, and that drag is moving its handle.
  void _onPointerDown(PointerDownEvent event) {
    final selected = _selectionRange;
    // A caret (an empty selection, which a tap on text leaves) is not a
    // selection anyone is working on.
    _pointerStart = selected == null || selected.end <= selected.start
        ? (at: event.localPosition, time: event.timeStamp, kind: event.kind)
        : null;
  }

  void _onPointerUp(PointerUpEvent event, double width) {
    final start = _pointerStart;
    _pointerStart = null;
    if (start == null || !_paged) return;
    final delta = event.localPosition - start.at;
    final elapsed = event.timeStamp - start.time;
    if (delta.distance < kTouchSlop && elapsed < kLongPressTimeout) {
      _onPagedTap(start.at.dx, width);
      return;
    }
    // A mouse drag is a selection, never a swipe.
    if (start.kind == PointerDeviceKind.mouse) return;
    final turn = swipeTurn(
      delta: delta,
      elapsed: elapsed,
      paged: true,
      atRestingZoom: true,
    );
    if (turn == null) return;
    // The drag selected text on its way across; that was not what it meant.
    _selectionArea.currentState?.selectableRegion.clearSelection();
    turn == SwipeTurn.forward ? _pageForward(_count) : _pageBack(_count);
  }

  /// Paged mode's taps: the left third goes back, the right third forward, and
  /// the middle does what a tap does in scrolled mode.
  void _onPagedTap(double x, double width) {
    if (x < width / 3) {
      _pageBack(_count);
    } else if (x > width * 2 / 3) {
      _pageForward(_count);
    } else if (_settings?.immersive == true) {
      _setReadingMode(!_chromeHidden);
    }
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
    _searchFocus.dispose();
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
    if (!had && next != null && _chromeHidden && mounted &&
        // Not mid-swipe: a sideways drag selects on its way across.
        _pointerStart == null) {
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
      locator:
          EpubScrollLocator(chapter: _chapter, fraction: _positionFraction),
    );
    if (!mounted) return;
    setState(() => _bookmarkOnChapter = id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(L10n.of(context).readerBookmarkedChapter(_chapter + 1))),
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
          .showSnackBar(SnackBar(content: Text(L10n.of(context).readerSelectTextFirst)));
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
      SnackBar(
          content: Text(withNote
              ? L10n.of(context).readerNoteSaved
              : L10n.of(context).readerHighlighted)),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10n.of(context).readerSelectWord),
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
        SnackBar(content: Text(L10n.of(context).readerNoTextToSend)),
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
          .showSnackBar(SnackBar(content: Text(L10n.of(context).readerSelectTextFirst)));
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
    final l10n = L10n.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerNoteOnPassageTitle),
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
              decoration: InputDecoration(hintText: l10n.readerNoteHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    return saved == true ? controller.text : null;
  }

  /// Opens the search, or — if it is already open — puts the caret back in it
  /// with the old query selected.
  void _openSearch() {
    if (_loaded == null) return;
    if (!_searching) {
      // Reading mode hides the bar the box lives in.
      if (_chromeHidden) _setReadingMode(false);
      setState(() => _searching = true);
    }
    // After the frame, because on the first press the field does not exist yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) {
        focusSearchField(_searchFocus, _searchController);
      }
    });
  }

  void _closeSearch() {
    if (!_searching) return;
    _searchFocus.unfocus();
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
    final result = searchEpub(L10n.of(context), epub.chapters, query);
    setState(() {
      _hits = result.hits;
      _hitsTruncated = result.truncated;
      _hitIndex = 0;
    });
    if (_hits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).readerNoMatch(query.trim()))),
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
    _jumpInChapter(hit.fraction);
  }

  /// Moves to [fraction] of the current chapter, in either layout — after the
  /// frame in scrolled mode, because a chapter just switched to has no extent
  /// yet. Paged mode needs no wait: the view resolves the anchor itself once
  /// the chapter is laid out.
  void _jumpInChapter(double fraction) {
    final f = fraction.clamp(0.0, 1.0).toDouble();
    if (_paged) {
      setState(() => _anchor = AtScrollFraction(f));
      _savePositionSoon();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) _scroll.jumpTo(f * max);
    });
  }

  /// Go to chapter N. Chapters are what this reader turns, and what the saved
  /// position counts, so they are the unit the box asks for.
  Future<void> _promptChapterJump() async {
    final count = _count;
    if (count <= 0) return; // the book hasn't opened yet
    final controller = TextEditingController();
    final l10n = L10n.of(context);
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readerGoToChapterTitle(count)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (value) =>
              Navigator.pop(dialogContext, int.tryParse(value)),
          decoration: InputDecoration(hintText: l10n.readerChapterNumberHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: Text(l10n.readerGo),
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
            _jumpInChapter(target.fraction);
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
    if (!_paged) _savePositionSoon();
  }

  void _savePositionSoon() {
    if (_count == 0) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      final fraction = _positionFraction;
      widget.repository.saveEpubPosition(
        widget.book.id,
        chapterIndex: _chapter,
        chapterCount: _count,
        scrollFraction: fraction,
      );
      _saveFilePosition(_count, fraction);
    });
  }

  /// The same position, against this *file* — so an EPUB and a PDF of one book
  /// keep their places apart (8/25 request).
  void _saveFilePosition(int count, double scrollFraction) {
    final bookFile = widget.bookFile;
    if (bookFile == null || count == 0) return;
    widget.repository.readingPositions.saveFilePosition(
      fileId: bookFile.id,
      bookId: widget.book.id,
      progress: ((_chapter + scrollFraction.clamp(0, 1)) / count)
          .clamp(0, 1)
          .toDouble(),
      page: _chapter + 1,
      scroll: scrollFraction,
    );
  }

  /// One screenful forward, rolling into the next chapter at the end.
  ///
  /// The unit people mean by "page" here is a screenful, not a chapter: tapping
  /// the right edge repeatedly should walk through the book, and stopping dead
  /// at the bottom of every chapter would make the gesture useless exactly
  /// where it is most wanted.
  void _pageForward(int count) {
    if (_paged) {
      final pages = _pages;
      if (pages == null || !pages.ready) return; // still laying out
      final page = pages.pageFor(_anchor);
      if (page < pages.count - 1) {
        _turnTo(pages, page + 1);
      } else if (_chapter < count - 1) {
        _goTo(_chapter + 1, count);
      }
      return;
    }
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
    if (_paged) {
      final pages = _pages;
      if (pages == null || !pages.ready) return;
      final page = pages.pageFor(_anchor);
      if (page > 0) {
        _turnTo(pages, page - 1);
      } else if (_chapter > 0) {
        // The previous chapter's last page, not its first.
        _goTo(_chapter - 1, count, fraction: 1);
      }
      return;
    }
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

  /// A page turn inside the chapter: the view repaints, nothing is laid out.
  void _turnTo(ChapterPages pages, int page) {
    setState(() => _anchor = AtContentFraction(pages.contentFractionOf(page)));
    _savePositionSoon();
  }

  /// Opens chapter [index] at [fraction] — the top unless asked otherwise
  /// (paged mode going back lands on the previous chapter's last page).
  void _goTo(int index, int count, {double fraction = 0}) {
    final target = index.clamp(0, count - 1);
    final changed = target != _chapter;
    setState(() {
      _chapter = target;
      _anchor = AtScrollFraction(fraction);
      // The old chapter's pages say nothing about this one; turns wait for it.
      if (changed) _pages = null;
    });
    _session.touch(page: _chapter + 1);
    _refreshBookmark();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // Save immediately — a new chapter is worth more than a debounce.
    _saveDebounce?.cancel();
    widget.repository.saveEpubPosition(
      widget.book.id,
      chapterIndex: _chapter,
      chapterCount: count,
      scrollFraction: fraction,
    );
    _saveFilePosition(count, fraction);
  }

  /// Restore the saved in-chapter scroll after the first layout: the global
  /// fraction minus the chapters below gives this chapter's fraction.
  void _restoreScroll(int count) {
    // Paged mode resolves this itself once the chapter is laid out.
    _anchor = AtScrollFraction(epubPositionFrom(
      progress: widget.book.readingProgress,
      lastReadPage: widget.book.lastReadPage,
      chapterCount: count,
    ).fraction);
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
          title: Text(epub.chapters[i].titleOf(L10n.of(context), i),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.pop(sheetContext, i),
        ),
      ),
    );
    if (picked != null && mounted) _goTo(picked, epub.chapters.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return FutureBuilder<EpubBook>(
      future: _epub,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.book.title)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.readerEpubOpenFailed('${snapshot.error}')),
              ),
            ),
          );
        }
        final epub = snapshot.data;
        // The settings too: they decide scrolled or paged, and starting in the
        // wrong one would restore the position into a view about to vanish.
        if (epub == null || _settings == null) {
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
          _chapter = widget.initialChapter?.clamp(0, count - 1) ??
              epubPositionFrom(
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
        // The chapter's pages, when paged mode has them for this chapter.
        final pages = _paged && (_pages?.ready ?? false) ? _pages : null;
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
                ? ReaderSearchField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    foreground: readerTheme.foreground,
                    onSubmitted: _runSearch,
                  )
                : Text(widget.book.title),
            actions: [
              if (_searching) ...[
                if (_hits.isNotEmpty)
                  Center(
                    child: Text(
                      '${_hitIndex + 1}/${_hits.length}'
                      '${_hitsTruncated ? '+' : ''}',
                      style: TextStyle(color: readerTheme.foreground),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: l10n.readerSearchPrevious,
                  style: readerSearchIconStyle(readerTheme.foreground),
                  onPressed: _hits.isEmpty ? null : () => _stepHit(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: l10n.readerSearchNext,
                  style: readerSearchIconStyle(readerTheme.foreground),
                  onPressed: _hits.isEmpty ? null : () => _stepHit(1),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.readerSearchClose,
                  style: readerSearchIconStyle(readerTheme.foreground),
                  onPressed: _closeSearch,
                ),
              ],
              if (!_searching) ...[
              // The counter is the obvious place to press when you want a
              // particular chapter, so it is the control rather than a label.
              // Hold it to change what it counts, exactly as in the PDF
              // reader. An EPUB counts chapters rather than pages, so *time
              // left* has nothing to measure and is left out of the cycle here.
              //
              // Width-capped for the same reason as the PDF reader's: the
              // budget below has to know what it costs.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kCounterWidth),
                child: GestureDetector(
                  onLongPress: () {
                    final s = _settings;
                    if (s == null) return;
                    var next = s.pageMetric.next;
                    if (next == PageMetric.timeLeft) next = next.next;
                    s.setPageMetric(next);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(next.labelOf(l10n)),
                        duration: const Duration(milliseconds: 900),
                      ),
                    );
                  },
                  child: TextButton(
                    onPressed: _promptChapterJump,
                    style: TextButton.styleFrom(
                      foregroundColor: readerTheme.foreground,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      pageMetricLabel(
                        l10n,
                        settings?.pageMetric ?? PageMetric.pagesOf,
                        page: _chapter + 1,
                        count: count,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              // What fits, then a menu — see `reader_actions.dart`. This bar
              // is the longer of the two readers', so it overflowed first.
              ReaderActionBar(
                foreground: readerTheme.foreground,
                reserved: kLeadingWidth + kCounterWidth,
                actions: [
                  if (_selectionRange != null) ...[
                    ReaderAction(
                      icon: Icons.format_color_text,
                      color: _highlightColour.color,
                      label: l10n.readerActHighlightIn(
                          _highlightColour.labelOf(l10n)),
                      onPressed: () => _highlightSelection(epub),
                    ),
                    if (settings != null)
                      ReaderAction(
                        icon: Icons.palette_outlined,
                        label: l10n.readerActHighlighterColour(
                            _highlightColour.labelOf(l10n)),
                        onPressed: () => showHighlightColorSheet(
                          context,
                          selected: _highlightColour,
                          onChanged: (colour) =>
                              settings.setHighlightColor(colour.argb),
                        ),
                        widget: HighlightColorButton(
                          selected: _highlightColour,
                          onChanged: (colour) =>
                              settings.setHighlightColor(colour.argb),
                        ),
                      ),
                    ReaderAction(
                      icon: Icons.sticky_note_2_outlined,
                      label: l10n.readerActNoteOnSelection,
                      onPressed: () => _highlightSelection(epub, withNote: true),
                    ),
                    // A word, not a phrase — the same rule as the PDF reader.
                    if (_selectionIsWord)
                      ReaderAction(
                        icon: Icons.menu_book_outlined,
                        label: l10n
                            .readerActLookUp(singleWord(_selectedText(epub))!),
                        onPressed: () => _defineSelection(epub),
                      ),
                    ReaderAction(
                      icon: Icons.auto_awesome_outlined,
                      label: l10n.readerActAskModel,
                      onPressed: () => _askAi(epub),
                    ),
                    if (settings != null)
                      ReaderAction(
                        icon: Icons.translate,
                        label: l10n.readerActTranslate,
                        onPressed: () => _translateSelection(epub),
                      ),
                  ],
                  ReaderAction(
                    icon: _bookmarkOnChapter == null
                        ? Icons.bookmark_outline
                        : Icons.bookmark,
                    label: _bookmarkOnChapter == null
                        ? l10n.readerActBookmarkChapter
                        : l10n.readerActRemoveBookmark,
                    onPressed: _toggleBookmark,
                  ),
                  if (settings != null)
                    ReaderAction(
                      icon: _paged
                          ? Icons.swap_vert
                          : Icons.auto_stories_outlined,
                      label: _paged
                          ? l10n.readerActShowScrolled
                          : l10n.readerActShowPaged,
                      onPressed: () => settings.setEpubLayout(_paged
                          ? EpubLayout.scrolled
                          : EpubLayout.paged),
                    ),
                  // Scrolling by itself has nothing to scroll in paged mode.
                  if (!_paged)
                    ReaderAction(
                      icon: _autoScrolling
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      label: _autoScrolling
                          ? l10n.readerActAutoScrollStop
                          : l10n.readerActAutoScroll,
                      onPressed: _toggleAutoScroll,
                    ),
                  ReaderAction(
                    icon: Icons.fullscreen,
                    label: l10n.readerActReadingMode,
                    onPressed: () => _setReadingMode(true),
                  ),
                  ReaderAction(
                    icon: Icons.list_alt,
                    label: l10n.readerActAnnotations,
                    onPressed: () => _openPanel(epub),
                  ),
                  ReaderAction(
                    icon: Icons.search,
                    label: l10n.readerActSearch(commandModifierLabel()),
                    onPressed: _openSearch,
                  ),
                  ReaderAction(
                    icon: Icons.toc,
                    label: l10n.readerActChapters,
                    onPressed: () => _pickChapter(epub),
                  ),
                  ReaderAction(
                    icon: Icons.auto_awesome,
                    label: l10n.readerActAskModelChapter,
                    onPressed: () => _askAi(epub, wholeChapter: true),
                  ),
                  if (settings != null)
                    ReaderAction(
                      icon: Icons.text_fields,
                      label: l10n.readerActReadingOptions,
                      onPressed: () => ReaderSettingsSheet.show(
                        context,
                        settings: settings,
                        typography: true,
                      ),
                    ),
                ],
              ),
              ],
            ],
          ),
          body: LayoutBuilder(builder: (context, constraints) {
            final strip = ReaderEdgeTurn.stripWidth(
              constraints.maxWidth,
              settings?.measure ?? 720,
            );
            // The chapter itself, the same widget in both layouts — which is
            // what makes their line breaks, and so their positions, agree.
            //
            // Selectable so passages can be highlighted; the listener is what
            // turns a selection into character offsets (plan 5 #22). The
            // reader's typography applies to the book's text only — the UI
            // keeps following the system text scale. On a dark page the book's
            // own colours would otherwise win (a stylesheet saying `color:
            // #222` is black on black); its *pictures* are the factory's job.
            final chapterView = SelectionArea(
              key: _selectionArea,
              child: SelectionListener(
                selectionNotifier: _selectionNotifier,
                child: HtmlWidget(
                  _markup.of(
                    chapter,
                    index: _chapter,
                    darkPage: darkPage,
                    ink: readerTheme.foreground,
                    annotations: _bookAnnotations,
                  ),
                  textStyle: settings?.bodyTextStyle() ??
                      TextStyle(color: readerTheme.foreground),
                  customStylesBuilder: darkPage
                      ? (element) => element.localName == 'mark'
                          ? null
                          : {'color': cssHex(readerTheme.foreground)}
                      : null,
                  factoryBuilder:
                      dark ? NightModeFactory.new : ReaderHtmlFactory.new,
                ),
              ),
            );
            return Stack(children: [
              if (_paged)
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerUp: (event) =>
                      _onPointerUp(event, constraints.maxWidth),
                  child: Padding(
                    // The same insets as scrolled mode's scroll view, so the
                    // column is the same width and wraps the same way.
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: SafeArea(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: settings?.measure ?? 720,
                          ),
                          child: PagedChapterView(
                            key: ValueKey(_chapter),
                            anchor: _anchor,
                            onPaginated: _onPaginated,
                            child: chapterView,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
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
                    child: chapterView,
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
                      [
                        if (pages != null)
                          l10n.readerStatusOf(
                              'page', _pageInChapter + 1, pages.count),
                        readingModeStatus(
                          l10n,
                          page: _chapter + 1,
                          count: count,
                          unit: 'chapter',
                        ),
                      ].join('  ·  '),
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
                      unit: AutoScrollUnit.lines,
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
                tooltip: l10n.readerBackPage,
                colour: readerTheme.foreground,
                onTap: () => _pageBack(count),
              ),
              ReaderEdgeTurn(
                width: strip,
                alignment: Alignment.centerRight,
                icon: Icons.chevron_right,
                tooltip: l10n.readerForwardPage,
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          [
                            chapter.titleOf(l10n, _chapter),
                            if (pages != null)
                              l10n.readerChapterPageOf(
                                  _pageInChapter + 1, pages.count),
                          ].join('  ·  '),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // The bar takes the reader's page colour, so its
                          // text has to take the reader's ink — the app
                          // theme's would be dark-on-dark here.
                          style: TextStyle(color: readerTheme.foreground),
                        ),
                        // How far through the chapter, in paged mode — the
                        // scrollbar's job in scrolled mode.
                        if (pages != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 320),
                              child: LinearProgressIndicator(
                                value: pages.progressOf(_pageInChapter),
                                minHeight: 2,
                                color: readerTheme.foreground
                                    .withValues(alpha: 0.6),
                                backgroundColor: readerTheme.foreground
                                    .withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                      ],
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
