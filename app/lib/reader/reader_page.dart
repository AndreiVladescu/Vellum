import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../stats/stats_queries.dart';
import '../shortcuts.dart';
import 'ai/ai_settings.dart';
import 'ai/ask_ai_sheet.dart';
import 'auto_scroll.dart';
import 'dictionary/dictionary_sheet.dart';
import 'dictionary/wordnet.dart';
import 'auto_scroll_bar.dart';
import 'annotations/annotation_locator.dart';
import 'annotations/annotations_panel.dart';
import 'annotations/highlight_palette.dart';
import 'annotations/pdf_highlight_painter.dart';
import 'night_mode.dart';
import 'page_metric.dart';
import 'edge_turn.dart';
import 'reader_gestures.dart';
import 'reader_hotkeys.dart';
import 'pdf_paged_view.dart';
import 'reader_settings.dart';
import 'reader_settings_sheet.dart';
import 'translate/translate_sheet.dart';

/// The integrated PDF reader. Persists the current page as the user reads,
/// which drives the "Resume reading" state on the book's detail page, and lets
/// the reader leave bookmarks, highlights and notes (plan 5 #22).
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.book,
    required this.file,
    required this.repository,
    this.initialPage,
  });

  final Book book;
  final File file;
  final LibraryRepository repository;

  /// Open here instead of where you left off — how a content-search hit jumps
  /// straight to the page it matched on (plan 5 #32). The saved position is
  /// left alone until the reader records a new one, so a look at page 300
  /// doesn't quietly throw away your bookmark at page 12.
  final int? initialPage;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with SingleTickerProviderStateMixin {
  final _controller = PdfViewerController();
  int? _page;
  int? _pageCount;

  AnnotationStore get _annotations => widget.repository.annotations;

  /// Records this sitting (plan 5 #19). Opened on the first page report rather
  /// than in initState, so the session's start page is a real page number.
  late final SessionRecorder _session =
      SessionRecorder(widget.repository.db);

  /// The selected passages, resolved *while the selection is live*.
  ///
  /// pdfrx hands `onTextSelectionChange` the viewer's own selection object
  /// rather than a snapshot, and debounces the callback. Holding that object and
  /// asking it for its ranges later — on the button press, after a dialog took
  /// focus — is why highlighting sometimes silently did nothing: the check said
  /// there was a selection and the `await` came back empty.
  List<PdfPageTextRange> _selectedRanges = const [];

  bool get _hasSelection => _selectedRanges.isNotEmpty;

  /// Whether the current page already has a bookmark, so the action can toggle
  /// rather than stack duplicates. Refreshed on every page change.
  String? _bookmarkOnPage;

  /// Appearance settings (plan 5 #23).
  ReaderSettings? _settings;
  bool _chromeHidden = false;

  /// In-book text search. pdfrx does the work; this owns the query field's
  /// state and the match cursor.
  ///
  /// **Created only once the viewer is ready**, never in a field initialiser.
  /// `PdfTextSearcher`'s constructor calls `controller!.document`, and pdfrx's
  /// `controller` getter is null until a document is loaded — so building one
  /// during the first `build()` threw "Null check operator used on a null
  /// value" and no PDF would open at all. Null here simply means "search isn't
  /// available yet", which is true.
  PdfTextSearcher? _searcher;

  /// Draws stored highlights over the page (the "highlighter marker" look).
  /// Owns its own text cache, and asks for a repaint when a page's text lands.
  late final PdfHighlightPainter _highlights =
      PdfHighlightPainter(onNeedsRepaint: () {
    if (mounted) setState(() {});
  });
  StreamSubscription<List<Annotation>>? _annotationsSub;
  final _searchController = TextEditingController();
  bool _searching = false;

  /// Ctrl+F / Ctrl+G, which have to work before the page is clicked.
  late final ReaderHotkeys _hotkeys = ReaderHotkeys(
    isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
    onFind: _openSearch,
    onGoTo: _promptPageJump,
    onEscape: () {
      if (!_searching) return false;
      _closeSearch();
      return true;
    },
    isPaged: () => _mode == PdfPageMode.paged,
    onPageStep: _stepPage,
    onNudge: _nudge,
  );

  /// A whole page, in either mode.
  ///
  /// In paged mode that is what the viewer already does; in a continuous
  /// scroll it is a screenful, which is what Page Down means everywhere else
  /// and is not the same as "the next page boundary" — a scroll has no notion
  /// of landing on one.
  void _stepPage(int delta) {
    if (!_controller.isReady) return;
    if (_mode == PdfPageMode.paged) {
      final page = _page;
      if (page == null) return;
      final target = (page + delta).clamp(1, _controller.pageCount);
      if (target != page) _controller.goToPage(pageNumber: target);
      return;
    }
    _scrollBy(_controller.visibleRect.height * 0.9 * delta);
  }

  /// A few lines, for the arrow keys in a continuous scroll.
  void _nudge(int delta) {
    if (!_controller.isReady) return;
    _scrollBy(_controller.visibleRect.height * 0.12 * delta);
  }

  void _scrollBy(double dy) {
    _controller.goToPosition(
      documentOffset: _controller.centerPosition + Offset(0, dy),
      duration: const Duration(milliseconds: 120),
    );
  }

  @override
  void initState() {
    super.initState();
    // Hand the shelf's memory back before asking PDFium for page bitmaps. The
    // covers behind this page are worth hundreds of megabytes on a phone and
    // none of them are on screen now; the shelf re-decodes what it needs when
    // you come back, which is a moment of work against a reader that cannot
    // allocate a page at all.
    if (Platform.isAndroid || Platform.isIOS) {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    }
    _hotkeys.attach();
    _watchForASlowOpen();
    _loadPace();
    _annotationsSub =
        _annotations.watchForBook(widget.book.id).listen((annotations) {
      _highlights.update(annotations);
      if (mounted) setState(() {});
    });
    ReaderSettings.load().then((settings) {
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _chromeHidden = settings.immersive;
      });
      settings.addListener(_onSettingsChanged);
      // Re-anchor now that the real mode and fit are known.
      //
      // These settings arrive asynchronously, and the viewer is built before
      // they do — with the *defaults* (scroll mode, fit width). If the saved
      // mode or fit differs, the page was framed for one arrangement and then
      // laid out under another, and the viewport could end up off the page:
      // the reader opened blank. Opening it a second time hid the bug, because
      // by then the settings were already in memory and the first build had
      // them. `_applyFit` is a no-op until the document is ready, and
      // `onViewerReady` calls it too, so whichever of the two happens last is
      // the one that frames the page.
      _applyFit();
    });
  }

  void _watchForASlowOpen() {
    _openTimer?.cancel();
    _openTimer = Timer(_openTimeout, () {
      if (mounted && _page == null) setState(() => _slowToOpen = true);
    });
  }

  /// Builds the viewer again from scratch.
  ///
  /// pdfrx keys its document cache by path, so a second attempt is usually
  /// instant — which is exactly why closing the book and opening it again has
  /// been the workaround for a page that never arrives.
  void _retryOpen() {
    setState(() {
      _viewerAttempt++;
      _slowToOpen = false;
    });
    _watchForASlowOpen();
  }

  @override
  void dispose() {
    _autoTicker?.dispose();
    // The wakelock belongs to this page, not to the app.
    unawaited(WakelockPlus.disable().catchError((_) {}));
    _openTimer?.cancel();
    _hotkeys.detach();
    // Closing the session is fire-and-forget: the widget is going away, and a
    // dropped write costs one session row, not correctness.
    _session.end(page: _page);
    _annotationsSub?.cancel();
    _highlights.dispose();
    _searcher?.removeListener(_onSearchChanged);
    _searcher?.dispose();
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
  Future<void> _applyFit() async {
    final page = _page;
    if (page == null || !_controller.isReady) return;
    // Also what re-frames the page when the mode changes, so switching to
    // paged mode lands on a page rather than leaving you across a seam.
    _navigating = true;
    try {
      if (_settings?.pdfFit == PdfFit.page) {
        await _controller.goToPage(pageNumber: page, anchor: PdfPageAnchor.all);
      } else {
        await _fitWidth(page);
      }
    } finally {
      _navigating = false;
    }
  }

  /// Zooms so the page's *width* fills the viewport.
  ///
  /// **Not `goToPage`**, which is what this used to call and why *Fit width*
  /// appeared to do nothing while *Fit page* worked. pdfrx computes a fit as
  /// `min(viewW / rect.width, viewH / rect.height)` and then clamps it with
  /// `zoomMax: currentZoom` — so `goToPage` can only ever zoom *out*. Fitting a
  /// whole page usually is zooming out, so that one worked; fitting the width
  /// of a portrait page means zooming *in*, and the clamp swallowed it.
  ///
  /// `goToArea` applies no such clamp. Handing it a rect as wide as the page
  /// and shaped like the viewport makes both terms of that `min` equal
  /// `viewW / pageWidth`, which is fit-width exactly.
  Future<void> _fitWidth(int page) async {
    final pages = _controller.layout.pageLayouts;
    if (page < 1 || page > pages.length) return;
    final rect = pages[page - 1];
    final view = _controller.viewSize;
    if (view.width <= 0 || view.height <= 0) return;
    await _controller.goToArea(
      rect: Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width,
        rect.width * view.height / view.width,
      ),
      anchor: PdfPageAnchor.topCenter,
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
    // The document is up: whatever the clock was waiting for has happened.
    _openTimer?.cancel();
    setState(() {
      _slowToOpen = false;
      _page = page;
      _pageCount = _controller.pageCount;
    });
    // Fire-and-forget; tiny row update, safe to do per page turn.
    widget.repository.saveReadingPosition(
        widget.book.id, page, _controller.pageCount);
    _session.begin(widget.book.id, page: page).then((_) {
      _session.touch(page: page);
    });
    _refreshBookmark(page);
  }

  /// The marker currently in hand. A setting, not a question asked per
  /// highlight — see [HighlightColorButton].
  HighlightColor get _highlightColour =>
      HighlightColor.fromArgb(_settings?.highlightColor);

  /// The mode in force, before the settings have finished loading.
  PdfPageMode get _mode => _settings?.pdfMode ?? PdfPageMode.scroll;

  /// Where a pointer went down, and when — the two numbers a swipe is made of.
  ///
  /// A raw [Listener] rather than a `GestureDetector`: pdfrx runs its own pan
  /// and zoom recognisers on the same pixels, and a competing recogniser would
  /// have to win the arena to see anything, which would cost the panning that
  /// is the viewer's whole job. A Listener observes without competing, and
  /// these fields are what it observes.
  Offset? _pointerDownAt;
  DateTime? _pointerDownTime;

  /// While a mostly-vertical drag is in progress in continuous mode, the
  /// horizontal offset it started at. [_clamp] pins the viewport to it, so a
  /// page you have zoomed into does not wander sideways while you read down it
  /// (next features: the axis-lock request).
  double? _lockedX;

  /// Set once a drag has committed to being vertical, so a diagonal wobble
  /// early in a gesture cannot flip it back and forth.
  bool _axisDecided = false;

  /// Bumped to build a fresh viewer, which is what *Try again* does — the same
  /// thing closing the book and opening it again does, without the trip.
  int _viewerAttempt = 0;

  /// Set when the document has taken long enough that something is wrong.
  bool _slowToOpen = false;
  Timer? _openTimer;

  /// How long a document may take before the reader stops pretending it is
  /// about to appear. Measured against a 46 MB PDF opening in 150 ms on a
  /// phone; anything past this is not slow, it is stuck.
  static const _openTimeout = Duration(seconds: 8);

  /// True while a jump is animating, which suspends [_clamp].
  ///
  /// The clamp holds the viewport inside the page nearest its centre; during a
  /// turn the centre is briefly between two pages, and clamping those in-between
  /// frames makes the animation stagger. The destination is already a page, so
  /// there is nothing to enforce until it arrives.
  bool _navigating = false;

  /// The previous or next page. Only reachable in [PdfPageMode.paged] — in
  /// scrolling mode the edges are not there, because scrolling is the control.
  Future<void> _step(int direction) async {
    if (!_controller.isReady) return;
    final page = _page;
    final count = _pageCount;
    if (page == null || count == null) return;
    final target = page + direction;
    if (target < 1 || target > count) return;
    _navigating = true;
    try {
      await _controller.goToPage(
        pageNumber: target,
        anchor: _settings?.pdfFit == PdfFit.page
            ? PdfPageAnchor.all
            : PdfPageAnchor.topCenter,
      );
    } finally {
      _navigating = false;
    }
  }

  /// Pages a minute, from this reader's own recorded sittings. Null until
  /// there is enough history to measure, which the counter handles by falling
  /// back to a percentage rather than inventing a time.
  double? _pace;

  Future<void> _loadPace() async {
    final db = widget.repository.db;
    final sessions = await db.select(db.readingSessions).get();
    if (!mounted) return;
    setState(() => _pace = ReadingStats.pagesPerMinute(sessions));
  }

  /// Enters or leaves reading mode.
  ///
  /// Reading mode is the chrome gone — no toolbar, no scroll thumb — and the
  /// screen kept awake, because reading is the one thing you do with a phone
  /// without touching it, and a page that dims halfway down is the reason
  /// people tap at nothing. Leaving it puts the screen back on the system's
  /// own timeout.
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

  /// The self-scroller: a ticker, the offset it is driving, and whether a
  /// finger is currently on the page (next features: "scroll for you slowly,
  /// continuously").
  ///
  /// It moves the viewport's own translation rather than animating a jump,
  /// because the point is continuous motion — a series of `goTo` animations
  /// would arrive in steps, which is the reading-by-page-turn it replaces.
  Ticker? _autoTicker;
  Duration _autoLastTick = Duration.zero;
  double? _autoY;
  int _autoStuckFrames = 0;

  /// While a finger is down the scroller holds still, so you can drag the page
  /// where you want it and have it carry on from there when you let go.
  bool _autoHeld = false;

  bool get _autoScrolling => _autoTicker?.isActive ?? false;

  /// The speed in force: what you last set, or your own measured pace, or a
  /// slow default. Never a fabricated pace presented as measured — see
  /// [defaultAutoScrollPagesPerMinute].
  double get _autoSpeed => clampAutoScrollSpeed(
        _settings?.autoScrollPagesPerMinute ??
            _pace ??
            defaultAutoScrollPagesPerMinute,
        min: minAutoScrollPagesPerMinute,
        max: maxAutoScrollPagesPerMinute,
      );

  /// The current page as drawn, which is what "a page a minute" means on screen.
  double get _pageHeightOnScreen {
    final page = _page;
    if (page == null || !_controller.isReady) return 0;
    final pages = _controller.layout.pageLayouts;
    if (page < 1 || page > pages.length) return 0;
    return pages[page - 1].height * _controller.currentZoom;
  }

  void _toggleAutoScroll() {
    if (_autoScrolling) {
      _stopAutoScroll();
    } else {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    if (_mode != PdfPageMode.scroll || !_controller.isReady) return;
    // A drag that ended in a lock would otherwise pin the horizontal offset for
    // the whole of the scroll.
    _lockedX = null;
    _axisDecided = false;
    _autoY = null;
    _autoHeld = false;
    _autoStuckFrames = 0;
    _autoLastTick = Duration.zero;
    _autoTicker ??= createTicker(_onAutoTick);
    _autoTicker!.start();
    setState(() {});
  }

  void _stopAutoScroll() {
    _autoTicker?.stop();
    _autoY = null;
    if (mounted) setState(() {});
  }

  void _onAutoTick(Duration elapsed) {
    final seconds = (elapsed - _autoLastTick).inMicroseconds /
        Duration.microsecondsPerSecond;
    _autoLastTick = elapsed;
    // A long gap means the app was away; skip it rather than lurching.
    if (_autoHeld || seconds <= 0 || seconds > 0.5 || !_controller.isReady) {
      return;
    }
    final speed = autoScrollPixelsPerSecond(
      unitsPerMinute: _autoSpeed,
      unitHeightPixels: _pageHeightOnScreen,
    );
    if (speed <= 0) return;
    final before = _controller.value.row1[3];
    // Driven from our own running offset, not from the matrix: at a slow speed
    // a frame moves a third of a pixel, and reading the position back each time
    // would round that away to nothing. Re-synced whenever something else — a
    // drag, a jump — has moved the page out from under us.
    var target = _autoY;
    if (target == null || (target - before).abs() > 2) target = before;
    target -= speed * seconds;
    _controller.value = _controller.value.clone()..setEntry(1, 3, target);
    final after = _controller.value.row1[3];
    _autoY = after;
    // The clamp refuses to move past the last page, so a run of frames that
    // went nowhere is the end of the document.
    if ((after - before).abs() < 0.05) {
      if (++_autoStuckFrames >= autoScrollStuckFrames) _stopAutoScroll();
    } else {
      _autoStuckFrames = 0;
    }
  }

  Future<void> _setAutoSpeed(double pagesPerMinute) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setAutoScrollPagesPerMinute(roundAutoScrollSpeed(
      clampAutoScrollSpeed(
        pagesPerMinute,
        min: minAutoScrollPagesPerMinute,
        max: maxAutoScrollPagesPerMinute,
      ),
    ));
  }

  /// True when the page is shown whole, rather than zoomed into.
  ///
  /// The test that decides whether a swipe turns the page or pans it: once you
  /// have zoomed in, dragging is how you look around the page, and stealing
  /// that to turn pages would make a zoomed page unreadable. A small tolerance
  /// because a "fit" zoom is rarely exactly the fit zoom after an animation.
  bool get _atRestingZoom {
    if (!_controller.isReady) return false;
    final page = _page;
    if (page == null) return false;
    final pages = _controller.layout.pageLayouts;
    if (page < 1 || page > pages.length) return false;
    final rect = pages[page - 1];
    final view = _controller.viewSize;
    if (rect.width <= 0 || view.width <= 0) return false;
    final fit = _settings?.pdfFit == PdfFit.page
        ? math.min(view.width / rect.width, view.height / rect.height)
        : view.width / rect.width;
    return _controller.currentZoom <= fit * 1.05;
  }

  void _onPointerDown(PointerDownEvent event) {
    // Holds the self-scroller still rather than stopping it: touching the page
    // to steady it is not the same as wanting to stop reading.
    if (_autoScrolling) _autoHeld = true;
    _pointerDownAt = event.position;
    _pointerDownTime = DateTime.now();
    _lockedX = null;
    _axisDecided = false;
  }

  /// Decides, once per drag, whether this is a vertical one — and if it is,
  /// remembers where it started horizontally so [_clamp] can hold it there.
  void _onPointerMove(PointerMoveEvent event) {
    if (_axisDecided || _mode != PdfPageMode.scroll) return;
    final from = _pointerDownAt;
    if (from == null) return;
    final delta = event.position - from;
    if (!axisDecided(delta)) return;
    _axisDecided = true;
    if (isVerticalDrag(delta) && !_atRestingZoom) {
      _lockedX = _controller.value.row0[3];
    }
  }

  /// A swipe, if that is what it was: page turns in paged mode.
  void _onPointerUp(PointerUpEvent event) {
    _autoHeld = false;
    final from = _pointerDownAt;
    final at = _pointerDownTime;
    _pointerDownAt = null;
    _pointerDownTime = null;
    _lockedX = null;
    _axisDecided = false;
    if (from == null || at == null) return;
    final turn = swipeTurn(
      delta: event.position - from,
      elapsed: DateTime.now().difference(at),
      paged: _mode == PdfPageMode.paged,
      atRestingZoom: _atRestingZoom,
    );
    if (turn == null) return;
    _step(turn == SwipeTurn.forward ? 1 : -1);
  }

  /// Pins the viewport inside one page, so paged mode is genuinely paged: you
  /// cannot scroll a second page into view, and you cannot come to rest across
  /// the seam between two. See [clampToPage].
  Matrix4 _clamp(
    Matrix4 matrix,
    Size viewSize,
    PdfPageLayout layout,
    PdfViewerController? controller,
  ) {
    if (_navigating ||
        controller == null ||
        !controller.isReady ||
        layout.pageLayouts.isEmpty) {
      return matrix;
    }
    // Continuous mode's only rule: while a vertical drag is in progress on a
    // page you have zoomed into, the horizontal offset does not move. Reading
    // down a zoomed column and drifting sideways off the text is the thing
    // being fixed; nothing else about panning changes.
    if (_mode != PdfPageMode.paged) {
      // This hook *replaces* pdfrx's own boundary clamp rather than adding to
      // it, so continuous mode has to ask for it back — without it the document
      // can be dragged off into empty space, and the self-scroller would never
      // find a bottom to stop at.
      final bounded = controller.calcMatrixForClampedToNearestBoundary(
        matrix,
        viewSize: viewSize,
      );
      final lockedX = _lockedX;
      if (lockedX == null) return bounded;
      final held = bounded.clone();
      held.setEntry(0, 3, lockedX);
      return held;
    }
    final zoom = matrix.zoom;
    if (zoom <= 0) return matrix;
    final centre = matrix.calcPosition(viewSize);
    final page = layout.pageLayouts[nearestPage(layout.pageLayouts, centre)];
    final clamped = clampToPage(
      centre: centre,
      page: page,
      viewport: Size(viewSize.width / zoom, viewSize.height / zoom),
    );
    if (clamped == centre) return matrix;
    return controller.calcMatrixFor(clamped, zoom: zoom, viewSize: viewSize);
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
  /// Translates what is selected, and offers to keep the result as a note on
  /// the passage — which is the annotation the note button already writes, so a
  /// translation ends up in the same list as everything else you marked.
  /// The selection as a single word, if that is what it is — the dictionary
  /// was asked for words, not phrases (see [singleWord]).
  String? get _selectedWord => _selectedRanges.isEmpty
      ? null
      : singleWord(_selectedRanges.map((r) => r.text).join(' '));

  Future<void> _defineSelection() async {
    final word = _selectedWord;
    if (word == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select a single word to look it up.'),
      ));
      return;
    }
    final first = _selectedRanges.first;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DictionarySheet(
        word: word,
        onSaveAsNote: (definition) => _annotations.add(
          bookId: widget.book.id,
          kind: AnnotationKind.note,
          page: first.pageNumber,
          locator: PdfTextLocator(
            page: first.pageNumber,
            start: first.start,
            end: first.end,
          ),
          quotedText: word,
          note: definition,
          color: _highlightColour.argb,
        ),
      ),
    );
  }

  /// The model's settings, loaded the first time something asks for them —
  /// most sittings never do.
  AiSettings? _ai;

  Future<AiSettings> _aiSettings() async => _ai ??= await AiSettings.load();

  /// Sends the selection, or the page, to whatever model has been named.
  ///
  /// The page as a fallback because the request was about getting text *out of*
  /// the PDF, not only out of a selection: "what is this page about" is the
  /// question you have when you have not read it yet, so there is nothing
  /// selected to ask about.
  Future<void> _askAi({bool wholePage = false}) async {
    final page = _page;
    var passage = _selectedRanges.map((r) => r.text).join(' ').trim();
    var what = 'passage';
    if (wholePage || passage.isEmpty) {
      if (page == null) return;
      what = 'page';
      passage = await _controller.useDocument(
            (document) async =>
                (await document.pages[page - 1].loadStructuredText()).fullText,
          ) ??
          '';
      passage = passage.trim();
    }
    if (!mounted) return;
    if (passage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('There is no text here to send — this page may be a '
            'scan.'),
      ));
      return;
    }
    final settings = await _aiSettings();
    if (!mounted) return;
    final first = _selectedRanges.isEmpty ? null : _selectedRanges.first;
    final quoted = passage;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AskAiSheet(
        passage: quoted,
        settings: settings,
        bookTitle: widget.book.title,
        what: what,
        onSaveAsNote: (answer) => _annotations.add(
          bookId: widget.book.id,
          kind: AnnotationKind.note,
          page: first?.pageNumber ?? page,
          locator: first == null
              ? (page == null ? null : PdfPageLocator(page: page))
              : PdfTextLocator(
                  page: first.pageNumber,
                  start: first.start,
                  end: first.end,
                ),
          quotedText: first == null ? null : quoted,
          note: answer,
          color: _highlightColour.argb,
        ),
      ),
    );
  }

  Future<void> _translateSelection() async {
    final settings = _settings;
    final ranges = _selectedRanges;
    if (settings == null) return;
    if (ranges.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select some text first.')));
      return;
    }
    final passage = ranges.map((r) => r.text).join(' ').trim();
    final first = ranges.first;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TranslateSheet(
        passage: passage,
        settings: settings,

        onSaveAsNote: (translation) => _annotations.add(
          bookId: widget.book.id,
          kind: AnnotationKind.note,
          page: first.pageNumber,
          locator: PdfTextLocator(
            page: first.pageNumber,
            start: first.start,
            end: first.end,
          ),
          quotedText: passage,
          note: translation,
          color: _highlightColour.argb,
        ),
      ),
    );
  }

  Future<void> _highlightSelection({bool withNote = false}) async {
    final ranges = _selectedRanges;
    if (ranges.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select some text first.')));
      return;
    }

    final colour = _highlightColour;

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
        color: colour.argb,
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
    final dark = settings?.nightMode ?? false;
    final readerTheme = settings?.effectiveTheme ?? ReaderTheme.light;
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
                  _searcher?.startTextSearch(query.trim());
                },
              )
            : Text(widget.book.title),
        actions: [
          if (_searching) ...[
            if (_searcher?.hasMatches ?? false)
              Center(
                child: Text(
                  '${(_searcher!.currentIndex ?? 0) + 1}'
                  '/${_searcher!.matches.length}',
                ),
              ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous match',
              onPressed:
                  (_searcher?.hasMatches ?? false) ? _searcher!.goToPrevMatch : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next match',
              onPressed:
                  (_searcher?.hasMatches ?? false) ? _searcher!.goToNextMatch : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search (Esc)',
              onPressed: _closeSearch,
            ),
          ],
          if (!_searching) ...[
          if (_page != null && _pageCount != null)
            // The counter is the obvious place to press when you want a
            // particular page, so it is the control rather than a label with
            // the real one buried in the overflow menu.
            // The counter is the control: press it to go to a page, hold it
            // to change what it counts. A long book announcing its length on
            // every page turn is the thing being escaped.
            GestureDetector(
              onLongPress: () {
                final s = _settings;
                if (s == null) return;
                final next = s.pageMetric.next;
                s.setPageMetric(next);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(next.label),
                    duration: const Duration(milliseconds: 900),
                  ),
                );
              },
              child: TextButton(
                onPressed: _promptPageJump,
                style: TextButton.styleFrom(
                  foregroundColor: readerTheme.foreground,
                ),
                child: Text(pageMetricLabel(
                  settings?.pageMetric ?? PageMetric.pagesOf,
                  page: _page!,
                  count: _pageCount!,
                  pagesPerMinute: _pace,
                )),
              ),
            ),
          // Selection-dependent actions appear only while text is selected, so
          // the bar isn't a row of buttons that silently do nothing.
          if (_hasSelection) ...[
            IconButton(
              icon:
                  Icon(Icons.format_color_text, color: _highlightColour.color),
              tooltip: 'Highlight in ${_highlightColour.label}',
              onPressed: _highlightSelection,
            ),
            if (settings != null)
              HighlightColorButton(
                selected: _highlightColour,
                onChanged: (colour) => settings.setHighlightColor(colour.argb),
              ),
            IconButton(
              icon: const Icon(Icons.sticky_note_2_outlined),
              tooltip: 'Note on selection',
              onPressed: () => _highlightSelection(withNote: true),
            ),
            // Only for a single word, which is what was asked for: on a
            // paragraph the button would be there and return nothing, which
            // reads as broken. Unlike translation it is not gated on setup —
            // the sheet is where the dictionary is downloaded.
            if (_selectedWord != null)
              IconButton(
                icon: const Icon(Icons.menu_book_outlined),
                tooltip: 'Look up “${_selectedWord!}”',
                onPressed: _defineSelection,
              ),
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'Ask a model about this',
              onPressed: _askAi,
            ),
            // Always offered, because the sheet is also where translation is
            // set up: gating the button on a configured backend left the
            // desktop unable to reach the only screen that configures one.
            if (settings != null)
              IconButton(
                icon: const Icon(Icons.translate),
                tooltip: 'Translate selection',
                onPressed: _translateSelection,
              ),
          ],
          if (settings != null)
            IconButton(
              icon: Icon(settings.pdfMode == PdfPageMode.paged
                  ? Icons.auto_stories_outlined
                  : Icons.swap_vert),
              tooltip: '${settings.pdfMode.label} — switch to '
                  '${settings.pdfMode == PdfPageMode.paged ? PdfPageMode.scroll.label : PdfPageMode.paged.label}',
              onPressed: () => settings.setPdfMode(
                settings.pdfMode == PdfPageMode.paged
                    ? PdfPageMode.scroll
                    : PdfPageMode.paged,
              ),
            ),
          IconButton(
            icon: Icon(_bookmarkOnPage == null
                ? Icons.bookmark_outline
                : Icons.bookmark),
            tooltip: _bookmarkOnPage == null
                ? 'Bookmark this page'
                : 'Remove bookmark',
            onPressed: _page == null ? null : _toggleBookmark,
          ),
          // Scrolling by itself only means anything where scrolling is how you
          // move; in paged mode there is nothing to scroll.
          if (_mode == PdfPageMode.scroll)
            IconButton(
              icon: Icon(_autoScrolling
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline),
              tooltip: _autoScrolling
                  ? 'Stop scrolling by itself'
                  : 'Scroll by itself',
              onPressed: _controller.isReady ? _toggleAutoScroll : null,
            ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Reading mode — swipe down from the top to come back',
            onPressed: () => _setReadingMode(true),
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Annotations',
            onPressed: _openPanel,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search in this book (${commandModifierLabel()}F)',
            // Disabled until the document is loaded, which is also when the
            // searcher exists — a search box that silently does nothing is
            // worse than one that is visibly not ready yet.
            onPressed: _searcher == null ? null : _openSearch,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (choice) {
              switch (choice) {
                case 'jump':
                  _promptPageJump();
                case 'ask':
                  _askAi(wholePage: true);
                case 'options':
                  final s = _settings;
                  if (s != null) {
                    ReaderSettingsSheet.show(context, settings: s, pdf: true);
                  }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'jump',
                child: Text('Go to page…  ${commandModifierLabel()}G'),
              ),
              const PopupMenuItem(
                  value: 'ask', child: Text('Ask a model about this page…')),
              const PopupMenuItem(
                  value: 'options', child: Text('Reading options…')),
            ],
          ),
          ],
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        // A PDF has no measure to hang the strips off, so they take a tenth of
        // the width — which for a page fitted to the window is its own margin.
        final strip =
            ReaderEdgeTurn.stripWidth(constraints.maxWidth, constraints.maxWidth * 0.8);
        return Stack(children: [
          Listener(
            // Observes; does not compete. See [_onPointerDown].
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: GestureDetector(
            onTap: settings?.immersive == true
                ? () => _setReadingMode(!_chromeHidden)
                : null,
            child: nightModeWrap(
              enabled: dark,
              child: PdfViewer.file(
        widget.file.path,
        key: ValueKey(_viewerAttempt),
        controller: _controller,
        initialPageNumber: widget.initialPage ?? widget.book.lastReadPage ?? 1,
        params: PdfViewerParams(
          // pdfrx keeps 100 MB of rendered pages by default. That is a
          // desktop's budget: on a phone it lands on top of the shelf's covers
          // and the engine's own textures, and a reader only ever shows a page
          // or two at once. Measured on a 340-page PDF, the pages either side
          // of the one you are on cost a few megabytes.
          maxImageBytesCachedOnMemory:
              (Platform.isAndroid || Platform.isIOS) ? 32 << 20 : 100 << 20,
          // Inside the filter, so it has to be the colour that *inverts* to
          // the one we want: a dark background here would come out white.
          backgroundColor:
              dark ? ReaderTheme.light.background : readerTheme.background,
          onPageChanged: _onPageChanged,
          // Seven times pdfrx's default. Its 0.2 is a crawl on a desktop
          // mouse — a notch moved about ten pixels — and reading a PDF is
          // mostly wheel work.
          scrollByMouseWheel: 1.5,
          // The scrollbar belongs to scrolling. In paged mode there is nothing
          // for it to represent — you are on a page, not somewhere in a river.
          viewerOverlayBuilder: _mode == PdfPageMode.scroll && !_chromeHidden
              ? (context, size, handleLinkTap) => [
                    PdfViewerScrollThumb(
                      controller: _controller,
                      orientation: ScrollbarOrientation.right,
                      // Big enough to grab with a mouse without aiming.
                      thumbSize: const Size(32, 56),
                      margin: 4,
                    ),
                  ]
              : null,
          // Both modes: the page clamp when paged, the axis lock when not.
          normalizeMatrix: _clamp,
          onViewerReady: (_, _) {
            // `onPageChanged` only fires on a *change*, so until you scrolled
            // there was no current page: the counter was blank, Bookmark was
            // disabled, and the edge buttons — which turn from `_page` — did
            // nothing at all. Opening the book *is* arriving on a page.
            if (_page == null) _onPageChanged(_controller.pageNumber);
            _applyFit();
            // Now the controller has a document, so the searcher can exist.
            if (_searcher == null && mounted) {
              setState(() {
                _searcher = PdfTextSearcher(_controller)
                  ..addListener(_onSearchChanged);
              });
            }
          },
          // Draws the search highlights pdfrx maintains for the active query.
          pagePaintCallbacks: [
            // Highlights first, search matches on top: the transient thing you
            // are hunting for right now should win over the permanent one.
            _highlights.paint,
            if (_searcher != null) _searcher!.pageTextMatchPaintCallback,
          ],
          textSelectionParams: PdfTextSelectionParams(
            onTextSelectionChange: (selection) async {
              // Resolved here, while the selection is live, and kept as a
              // snapshot — see [_selectedRanges].
              final ranges = selection.hasSelectedText
                  ? (await selection.getSelectedTextRanges())
                      .where((r) => r.text.trim().isNotEmpty)
                      .toList()
                  : const <PdfPageTextRange>[];
              if (!mounted) return;
              // Only rebuild when something the toolbar shows changes: this
              // fires continuously while dragging. That is the presence of a
              // selection — and whether it is a single word, because that is
              // what decides if the dictionary button is there. Without the
              // second test, narrowing a three-word selection down to one word
              // never brings the button back.
              final had = _hasSelection;
              final hadWord = _selectedWord != null;
              _selectedRanges = ranges;
              if (ranges.isNotEmpty != had || (_selectedWord != null) != hadWord) {
                setState(() {});
              }
            },
          ),
        ),
      ),
            ),
          ),
          ),
          // A swipe down from the very top edge brings the chrome back, the way
          // a video player does. A deliberate gesture from a place nothing else
          // uses, rather than a tap: taps are how pages turn.
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
          // The speed control, shown only while the page is moving by itself —
          // and shown in reading mode too, because that is where it is used:
          // the chrome is gone and this is the one thing you still need.
          if (_autoScrolling)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: AutoScrollBar(
                  speed: _autoSpeed,
                  unit: 'pages',
                  min: minAutoScrollPagesPerMinute,
                  max: maxAutoScrollPagesPerMinute,
                  onSpeed: _setAutoSpeed,
                  onStop: _stopAutoScroll,
                ),
              ),
            ),
          // Until the document reports in there is nothing to look at but the
          // background, and a blank page is indistinguishable from a broken
          // one. Say which it is.
          if (_page == null)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_slowToOpen,
                child: ColoredBox(
                  color: readerTheme.background,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_slowToOpen) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text('Opening…',
                              style: TextStyle(color: readerTheme.foreground)),
                        ] else ...[
                          Icon(Icons.hourglass_disabled,
                              size: 40, color: readerTheme.foreground),
                          const SizedBox(height: 12),
                          Text(
                            'This book is taking longer than it should.',
                            style: TextStyle(color: readerTheme.foreground),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _retryOpen,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // The same edge controls as the EPUB reader, so the two readers turn
          // the same way — but only where turning is the way you move. In
          // scrolling mode they would be a second, worse scrollbar, and the
          // right-hand one sat on top of the real one and ate its drags.
          if (_mode == PdfPageMode.paged) ...[
            ReaderEdgeTurn(
              width: strip,
              alignment: Alignment.centerLeft,
              icon: Icons.chevron_left,
              tooltip: 'Back a page',
              colour: readerTheme.foreground,
              onTap: () => _step(-1),
            ),
            ReaderEdgeTurn(
              width: strip,
              alignment: Alignment.centerRight,
              icon: Icons.chevron_right,
              tooltip: 'Forward a page',
              colour: readerTheme.foreground,
              onTap: () => _step(1),
            ),
          ],
        ]);
      }),
    );
  }

  /// Opens the in-book search, if the document is loaded enough to have one.
  void _openSearch() {
    if (_searcher == null || _searching) return;
    setState(() => _searching = true);
  }

  void _closeSearch() {
    if (!_searching) return;
    _searcher?.resetTextSearch();
    _searchController.clear();
    setState(() => _searching = false);
  }
}
