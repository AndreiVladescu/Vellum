import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
import 'annotations/ink_markup.dart';
import 'reader_actions.dart';
import 'annotations/ink_painter.dart';
import 'ink_tools.dart';
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

  /// Writing on the page (8/23 request). The painter holds what is stored; the
  /// live stroke is kept in view coordinates and drawn by an overlay, so a pen
  /// moving at sixty frames a second never touches the database or the matrix.
  final _ink = InkPainter();
  bool _penMode = false;
  InkTool _tool = InkTool.pen;
  int _inkColor = inkColors.first;
  double _inkWidth = inkWidths[1];
  /// The stroke under the pen, in view coordinates.
  ///
  /// A notifier rather than state: a pen moving at sixty frames a second would
  /// otherwise rebuild the whole reader — and with it the viewer's params — on
  /// every point. Only the overlay listens, and only the overlay repaints.
  final ValueNotifier<List<Offset>> _livePoints = ValueNotifier(const []);
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
      _ink.adopt(annotations);
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
    _livePoints.dispose();
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

  /// What the bar can do, in the order it gives things up.
  ///
  /// Selection actions come first on purpose: while text is selected they are
  /// the only reason the bar is being looked at, and the reading controls can
  /// wait in the menu for a moment.
  List<ReaderAction> _barActions(ReaderSettings? settings) => [
        if (_hasSelection) ...[
          ReaderAction(
            icon: Icons.format_color_text,
            color: _highlightColour.color,
            label: 'Highlight in ${_highlightColour.label}',
            onPressed: _highlightSelection,
          ),
          if (settings != null)
            ReaderAction(
              icon: Icons.palette_outlined,
              label: 'Highlighter colour — ${_highlightColour.label}',
              onPressed: () => showHighlightColorSheet(
                context,
                selected: _highlightColour,
                onChanged: (colour) => settings.setHighlightColor(colour.argb),
              ),
              widget: HighlightColorButton(
                selected: _highlightColour,
                onChanged: (colour) => settings.setHighlightColor(colour.argb),
              ),
            ),
          ReaderAction(
            icon: Icons.sticky_note_2_outlined,
            label: 'Note on selection',
            onPressed: () => _highlightSelection(withNote: true),
          ),
          if (_selectedWord != null)
            ReaderAction(
              icon: Icons.menu_book_outlined,
              label: 'Look up “${_selectedWord!}”',
              onPressed: _defineSelection,
            ),
          ReaderAction(
            icon: Icons.auto_awesome_outlined,
            label: 'Ask a model about this',
            onPressed: _askAi,
          ),
          if (settings != null)
            ReaderAction(
              icon: Icons.translate,
              label: 'Translate selection',
              onPressed: _translateSelection,
            ),
        ],
        if (settings != null)
          ReaderAction(
            icon: settings.pdfMode == PdfPageMode.paged
                ? Icons.auto_stories_outlined
                : Icons.swap_vert,
            label: '${settings.pdfMode.label} — switch to '
                '${settings.pdfMode == PdfPageMode.paged ? PdfPageMode.scroll.label : PdfPageMode.paged.label}',
            onPressed: () => settings.setPdfMode(
              settings.pdfMode == PdfPageMode.paged
                  ? PdfPageMode.scroll
                  : PdfPageMode.paged,
            ),
          ),
        ReaderAction(
          icon: _bookmarkOnPage == null ? Icons.bookmark_outline : Icons.bookmark,
          label: _bookmarkOnPage == null
              ? 'Bookmark this page'
              : 'Remove bookmark',
          onPressed: _page == null ? null : _toggleBookmark,
        ),
        if (_mode == PdfPageMode.scroll)
          ReaderAction(
            icon: _autoScrolling
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
            label: _autoScrolling
                ? 'Stop scrolling by itself'
                : 'Scroll by itself',
            onPressed: _controller.isReady ? _toggleAutoScroll : null,
          ),
        ReaderAction(
          icon: _penMode ? Icons.edit : Icons.edit_outlined,
          label: _penMode ? 'Stop writing' : 'Write on the page',
          selected: _penMode,
          onPressed: _controller.isReady ? () => _setPenMode(!_penMode) : null,
        ),
        ReaderAction(
          icon: Icons.fullscreen,
          label: 'Reading mode — swipe down from the top to come back',
          onPressed: () => _setReadingMode(true),
        ),
        ReaderAction(
          icon: Icons.list_alt,
          label: 'Annotations',
          onPressed: _openPanel,
        ),
        ReaderAction(
          icon: Icons.search,
          label: 'Search in this book (${commandModifierLabel()}F)',
          // Disabled until the document is loaded, which is also when the
          // searcher exists — a search box that silently does nothing is worse
          // than one that is visibly not ready yet.
          onPressed: _searcher == null ? null : _openSearch,
        ),
      ];

  /// The page under a point in the viewer's own coordinates, and where on that
  /// page it falls — 0,0 its top-left corner, 1,1 its bottom-right.
  ///
  /// Everything written is stored in those fractions rather than in pixels:
  /// see `ink_markup.dart`. This is the one place the two meet.
  ({int page, Offset at})? _pageAt(Offset local) {
    if (!_controller.isReady) return null;
    final inverse = Matrix4.tryInvert(_controller.value);
    if (inverse == null) return null;
    final document = MatrixUtils.transformPoint(inverse, local);
    final pages = _controller.layout.pageLayouts;
    for (var i = 0; i < pages.length; i++) {
      final rect = pages[i];
      if (!rect.contains(document)) continue;
      return (
        page: i + 1,
        at: Offset(
          (document.dx - rect.left) / rect.width,
          (document.dy - rect.top) / rect.height,
        ),
      );
    }
    return null;
  }

  /// The page the pen is working on. Fixed at the start of a stroke so a line
  /// that runs off the bottom of one page does not jump onto the next.
  int? _inkPage;

  /// Where a text-tool touch went down, to tell a tap from a drag.
  Offset? _textDownAt;

  /// What a drag in the select tool is doing, and what it started from.
  ///
  /// The original mark is kept so every move is computed from where the finger
  /// went down rather than accumulated frame by frame — accumulating is how a
  /// dragged object slowly drifts away from the finger.
  _InkDrag? _drag;

  void _onInkDown(PointerDownEvent event) {
    var hit = _pageAt(event.localPosition);
    if (hit == null) {
      // A note written in the margin has its corner handle off the paper. The
      // select tool still gets the event, aimed at the page the selection is
      // on; every other tool wants the finger on a page.
      final selectedPage = _ink.selectedPage;
      if (_tool != InkTool.select || selectedPage == null) return;
      final at = _fractionOn(selectedPage, event.localPosition);
      if (at == null) return;
      hit = (page: selectedPage, at: at);
    }
    _inkPage = hit.page;
    switch (_tool) {
      case InkTool.select:
        _beginSelectDrag(hit, event.localPosition);
      case InkTool.pen:
        _livePoints.value = [event.localPosition];
      case InkTool.eraser:
        _eraseAt(hit);
      case InkTool.text:
        // Placed on the way up, and only if the finger stayed put: a dialog
        // that opens at the end of a drag is one nobody asked for.
        _textDownAt = event.localPosition;
    }
  }

  void _onInkMove(PointerMoveEvent event) {
    final page = _inkPage;
    if (page == null) return;
    switch (_tool) {
      case InkTool.select:
        final drag = _drag;
        if (drag == null) return;
        // Through the matrix the drag started with: a pinch mid-drag would
        // otherwise make this finger position mean a different point on the
        // page, and the mark would jump.
        final at = _fractionOn(page, event.localPosition, matrix: drag.matrix);
        if (at != null) _moveSelection(at);
      case InkTool.pen:
        _livePoints.value = [..._livePoints.value, event.localPosition];
      case InkTool.eraser:
        final hit = _pageAt(event.localPosition);
        if (hit != null && hit.page == page) _eraseAt(hit);
      case InkTool.text:
        break;
    }
  }

  Future<void> _onInkUp(PointerUpEvent event) async {
    final page = _inkPage;
    _inkPage = null;
    if (page == null) return;
    switch (_tool) {
      case InkTool.select:
        await _endSelectDrag(page);
      case InkTool.pen:
        final points = _livePoints.value;
        _livePoints.value = const [];
        if (points.isEmpty) return;
        final fractions = <Offset>[];
        for (final point in points) {
          final hit = _pageAt(point);
          // Points that wandered onto another page (or off the document) are
          // dropped rather than clamped: a line should stop at the edge of the
          // paper, not fold along it.
          if (hit != null && hit.page == page) fractions.add(hit.at);
        }
        if (fractions.isEmpty) return;
        await _annotations.setInk(
          widget.book.id,
          page,
          _ink.markupOf(page).withStroke(InkStroke(
                points: fractions,
                color: _inkColor,
                width: _inkWidth,
              )),
        );
      case InkTool.eraser:
        await _commitErase(page);
      case InkTool.text:
        final from = _textDownAt;
        _textDownAt = null;
        if (from != null && (event.localPosition - from).distance > 10) return;
        final hit = _pageAt(event.localPosition);
        if (hit == null || hit.page != page) return;
        await _writeText(page, hit.at);
    }
  }

  /// Where the eraser has been during this drag, page-relative.
  ///
  /// The *path*, not the result: applying it to the stored page when the finger
  /// lifts means a stroke that arrived from another device mid-drag is erased
  /// too, rather than being overwritten by a snapshot taken before it existed.
  final List<Offset> _erasePath = [];

  /// Where the page under [page] is drawn, in the viewer's own coordinates —
  /// what the painter's text measurements are relative to.
  Rect? _pageRectOnScreen(int page) {
    if (!_controller.isReady) return null;
    final pages = _controller.layout.pageLayouts;
    if (page < 1 || page > pages.length) return null;
    return MatrixUtils.transformRect(_controller.value, pages[page - 1]);
  }

  /// Where [local] falls on [page], whether or not it is over the paper —
  /// and, when [matrix] is given, according to the view as it was *then*.
  ///
  /// Both matter for a drag: the corner handle of a note in the margin sits
  /// off the page, and a two-finger zoom mid-drag would otherwise make the
  /// same finger position mean a different point on the page and the mark
  /// jump. See [_InkDrag.matrix].
  Offset? _fractionOn(int page, Offset local, {Matrix4? matrix}) {
    if (!_controller.isReady) return null;
    final inverse = Matrix4.tryInvert(matrix ?? _controller.value);
    if (inverse == null) return null;
    final pages = _controller.layout.pageLayouts;
    if (page < 1 || page > pages.length) return null;
    final rect = pages[page - 1];
    if (rect.width <= 0 || rect.height <= 0) return null;
    final document = MatrixUtils.transformPoint(inverse, local);
    return Offset(
      (document.dx - rect.left) / rect.width,
      (document.dy - rect.top) / rect.height,
    );
  }

  /// The mark under a point, if any. Text is measured with the same painter
  /// that draws it, so what you can see is what you can grab.
  InkTarget? _markAt(({int page, Offset at}) hit) {
    final pageRect = _pageRectOnScreen(hit.page);
    if (pageRect == null) return null;
    return _ink.markupOf(hit.page).hitTest(
          hit.at,
          // A finger is wider than a pen line: the reach is the eraser's, so
          // a hairline stroke is still selectable.
          inkEraserRadius / 2,
          textBounds: (text) => textBoundsOnPage(text, pageRect),
        );
  }

  /// Whether the finger went down on the corner handle of the selected text —
  /// the one that turns it and changes its size.
  bool _onHandle(({int page, Offset at}) hit) {
    final target = _ink.selected;
    if (target == null ||
        target.kind != InkTargetKind.text ||
        _ink.selectedPage != hit.page) {
      return false;
    }
    final pageRect = _pageRectOnScreen(hit.page);
    if (pageRect == null) return false;
    final markup = _ink.markupOf(hit.page);
    if (target.index >= markup.texts.length) return false;
    final text = markup.texts[target.index];
    final box = textBoundsOnScreen(text, pageRect);
    final origin = fromPageFraction(text.at, pageRect);
    // The handle sits at the box's far corner, turned with the text.
    final corner = origin +
        rotateAbout(
          Offset(box.width + 3, box.height + 3),
          Offset.zero,
          text.rotation,
        );
    final finger = fromPageFraction(hit.at, pageRect);
    return (finger - corner).distance <= handleRadius * 2.5;
  }

  /// A touch in the select tool: the handle if it caught it, otherwise
  /// whatever mark is under the finger — and nothing is also an answer, since
  /// tapping the page is how you put a mark down.
  void _beginSelectDrag(({int page, Offset at}) hit, Offset local) {
    final markup = _ink.markupOf(hit.page);
    if (_onHandle(hit)) {
      final target = _ink.selected!;
      setState(() {
        _drag = _InkDrag(
          target: target,
          from: hit.at,
          matrix: _controller.value.clone(),
          text: markup.texts[target.index],
          handle: true,
        );
        _ink.pendingPage = hit.page;
        _ink.pending = markup;
      });
      return;
    }
    final target = _markAt(hit);
    setState(() {
      _ink.selected = target;
      _ink.selectedPage = target == null ? null : hit.page;
      _drag = target == null
          ? null
          : _InkDrag(
              target: target,
              from: hit.at,
              matrix: _controller.value.clone(),
              stroke: target.kind == InkTargetKind.stroke
                  ? markup.strokes[target.index]
                  : null,
              text: target.kind == InkTargetKind.text
                  ? markup.texts[target.index]
                  : null,
            );
      if (target != null) {
        _ink.pendingPage = hit.page;
        _ink.pending = markup;
      }
    });
  }

  /// Moving, or turning and resizing — on screen only, until the finger lifts.
  void _moveSelection(Offset at) {
    final drag = _drag;
    final page = _ink.pendingPage;
    if (drag == null || page == null) return;
    final stored = _ink.markupOf(page);
    setState(() {
      if (drag.handle) {
        final text = drag.text!;
        // The turn is the angle the finger has swept about the text's anchor;
        // the size is how much further away it has moved. One gesture, because
        // on paper turning a note and writing it bigger are one motion.
        final was = drag.from - text.at;
        final now = at - text.at;
        if (was.distance < 1e-6 || now.distance < 1e-6) return;
        final turn = math.atan2(now.dy, now.dx) - math.atan2(was.dy, was.dx);
        final scale = now.distance / was.distance;
        _ink.pending = stored.replacingText(
          drag.target.index,
          text.copyWith(
            rotation: text.rotation + turn,
            size: (text.size * scale)
                .clamp(minInkTextSize, maxInkTextSize)
                .toDouble(),
          ),
        );
        return;
      }
      final by = at - drag.from;
      _ink.pending = switch (drag.target.kind) {
        InkTargetKind.stroke =>
          stored.replacingStroke(drag.target.index, drag.stroke!.movedBy(by)),
        InkTargetKind.text =>
          stored.replacingText(drag.target.index, drag.text!.movedBy(by)),
      };
    });
  }

  /// Stores where it ended up, once.
  Future<void> _endSelectDrag(int page) async {
    final drag = _drag;
    final moved = _ink.pending;
    _drag = null;
    if (drag == null || moved == null) {
      setState(() {
        _ink.pending = null;
        _ink.pendingPage = null;
      });
      return;
    }
    setState(() {
      _ink.pending = null;
      _ink.pendingPage = null;
    });
    // A tap that selected something without moving it has nothing to store —
    // and storing it anyway would dirty the page and push an identical
    // payload to every other device.
    if (moved.encode() == _ink.markupOf(page).encode()) return;
    await _annotations.setInk(widget.book.id, page, moved);
  }

  /// Applies a change to the selected piece of text — the buttons' path, where
  /// the handle is the gesture's.
  Future<void> _changeSelectedText(InkText Function(InkText) change) async {
    final target = _ink.selected;
    final page = _ink.selectedPage;
    if (target == null || page == null || target.kind != InkTargetKind.text) {
      return;
    }
    final markup = _ink.markupOf(page);
    if (target.index >= markup.texts.length) return;
    await _annotations.setInk(
      widget.book.id,
      page,
      markup.replacingText(target.index, change(markup.texts[target.index])),
    );
  }

  Future<void> _editSelectedText() async {
    final target = _ink.selected;
    final page = _ink.selectedPage;
    if (target == null || page == null || target.kind != InkTargetKind.text) {
      return;
    }
    final markup = _ink.markupOf(page);
    if (target.index >= markup.texts.length) return;
    final words = await _promptForText(markup.texts[target.index].text);
    if (words == null) return;
    await _changeSelectedText((text) => text.copyWith(text: words));
  }

  Future<void> _deleteSelected() async {
    final target = _ink.selected;
    final page = _ink.selectedPage;
    if (target == null || page == null) return;
    setState(() {
      _ink.selected = null;
      _ink.selectedPage = null;
    });
    await _annotations.setInk(
      widget.book.id,
      page,
      _ink.markupOf(page).without(target),
    );
  }

  /// Rubs out what the eraser touched — on screen only, until the finger lifts.
  void _eraseAt(({int page, Offset at}) hit) {
    _erasePath.add(hit.at);
    final before = _ink.pendingPage == hit.page
        ? (_ink.pending ?? _ink.markupOf(hit.page))
        : _ink.markupOf(hit.page);
    final after = before.erasedAt(hit.at, inkEraserRadius);
    _ink.pendingPage = hit.page;
    if (after.strokes.length == before.strokes.length &&
        after.texts.length == before.texts.length) {
      _ink.pending = before;
      return;
    }
    setState(() => _ink.pending = after);
  }

  /// Stores what the eraser left behind, applied to the page as it stands now.
  Future<void> _commitErase(int page) async {
    final path = [..._erasePath];
    _erasePath.clear();
    setState(() {
      _ink.pending = null;
      _ink.pendingPage = null;
    });
    if (path.isEmpty) return;
    final stored = _ink.markupOf(page);
    var left = stored;
    for (final at in path) {
      left = left.erasedAt(at, inkEraserRadius);
    }
    if (left.strokes.length == stored.strokes.length &&
        left.texts.length == stored.texts.length) {
      return; // nothing was actually rubbed out
    }
    await _annotations.setInk(widget.book.id, page, left);
  }

  Future<void> _writeText(int page, Offset at) async {
    final text = await _promptForText('');
    if (text == null) return;
    await _annotations.setInk(
      widget.book.id,
      page,
      _ink.markupOf(page).withText(InkText(
            at: at,
            text: text,
            color: _inkColor,
            size: inkTextSize,
          )),
    );
  }

  /// The words for a note, new or being changed. Null when nothing was typed.
  Future<String?> _promptForText(String initial) async {
    final controller = TextEditingController(text: initial);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Write on the page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(hintText: 'A word in the margin'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Write'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return null;
    return text.trim();
  }

  /// Takes back the last mark on the page you are looking at.
  Future<void> _undoInk() async {
    final page = _page;
    if (page == null) return;
    final markup = _ink.markupOf(page);
    if (markup.isEmpty) return;
    await _annotations.setInk(widget.book.id, page, markup.withoutLast());
  }

  /// Enters or leaves writing mode.
  ///
  /// Turning it on stops the page moving under the pen: panning is off (pinch
  /// still zooms), text selection is off, and the self-scroller — which would
  /// slide the paper out from under a stroke — is stopped.
  void _setPenMode(bool on) {
    if (on) {
      _stopAutoScroll();
      _lockedX = null;
      _axisDecided = false;
    }
    setState(() {
      _penMode = on;
      _livePoints.value = const [];
      _ink.selected = null;
      _ink.selectedPage = null;
      _drag = null;
    });
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
    if (_mode != PdfPageMode.paged) {
      // This hook *replaces* pdfrx's own boundary clamp rather than adding to
      // it, so continuous mode has to ask for it back — without it the document
      // can be dragged off into empty space, and the self-scroller would never
      // find a bottom to stop at.
      final bounded = controller.calcMatrixForClampedToNearestBoundary(
        matrix,
        viewSize: viewSize,
      );
      final zoom = bounded.zoom;
      if (zoom <= 0) return bounded;
      // Sideways, the *page* is the limit rather than the document: pdfrx lays
      // the document out with margins, so its own clamp let you drag on past
      // the paper until there was background on both sides (8/26 report).
      // While a vertical drag is in progress the offset is held outright — the
      // axis lock — and otherwise it is held inside the page.
      final centre = bounded.calcPosition(viewSize);
      final page = layout.pageLayouts[nearestPage(layout.pageLayouts, centre)];
      final x = _lockedX == null
          ? clampToPageHorizontally(
              centreX: centre.dx,
              page: page,
              viewportWidth: viewSize.width / zoom,
            )
          : null;
      if (x == null) {
        final held = bounded.clone();
        held.setEntry(0, 3, _lockedX!);
        return held;
      }
      if (x == centre.dx) return bounded;
      return controller.calcMatrixFor(Offset(x, centre.dy),
          zoom: zoom, viewSize: viewSize);
    }
    final zoom = matrix.zoom;
    if (zoom <= 0) return matrix;
    // Paged mode at its resting zoom: the page is shown as it is meant to be
    // seen, so a drag has nothing to reveal. It used to shift the page a little
    // and *then* turn it, which read as a glitch (8/25 report: "it will move
    // momentarily, weirdly, and then it will page down"). Zooming is still
    // free — that is the one thing a drag here could usefully do — so only a
    // change that leaves the zoom alone is refused.
    if (_atRestingZoom &&
        (zoom - controller.currentZoom).abs() < 1e-6 &&
        !_penMode) {
      return controller.value;
    }
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
              // The counter is the control: press it to go to a page, hold it
              // to change what it counts. A long book announcing its length on
              // every page turn is the thing being escaped.
              //
              // Width-capped, because the bar's budget below has to know what
              // this costs — an uncapped counter would eat the buttons.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kCounterWidth),
                child: GestureDetector(
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
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      pageMetricLabel(
                        settings?.pageMetric ?? PageMetric.pagesOf,
                        page: _page!,
                        count: _pageCount!,
                        pagesPerMinute: _pace,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            // Everything else is measured against what is left of the row: on
            // a phone the last few fold into the menu instead of drawing over
            // the back arrow. See `reader_actions.dart`.
            ReaderActionBar(
              foreground: readerTheme.foreground,
              reserved: kLeadingWidth +
                  (_page != null && _pageCount != null ? kCounterWidth : 0),
              actions: _barActions(settings),
              menuExtras: [
                PopupMenuItem(
                  value: _promptPageJump,
                  child: Text('Go to page…  ${commandModifierLabel()}G'),
                ),
                PopupMenuItem(
                  value: () => _askAi(wholePage: true),
                  child: const Text('Ask a model about this page…'),
                ),
                PopupMenuItem(
                  value: () {
                    final s = _settings;
                    if (s == null) return;
                    ReaderSettingsSheet.show(context, settings: s, pdf: true);
                  },
                  child: const Text('Reading options…'),
                ),
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
          // A one-finger drag draws instead of panning while the pen is out;
          // pinch-to-zoom is left alone, so you can still move the page.
          panEnabled: !_penMode,
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
            // Writing goes over the marker, the way it does on paper.
            _ink.paint,
            if (_searcher != null) _searcher!.pageTextMatchPaintCallback,
          ],
          textSelectionParams: PdfTextSelectionParams(
            // A dragged finger is a pen stroke now, not a selection.
            enabled: !_penMode,
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
              // Selecting text is asking for the toolbar: highlight, note,
              // look up, translate all live there. Only on the edge where a
              // selection *appears* — clearing it leaves you out of reading
              // mode, because the next thing you do is one of those.
              if (!had && ranges.isNotEmpty && _chromeHidden) {
                _setReadingMode(false);
              }
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
          // The pen layer. A Listener rather than a GestureDetector for the
          // same reason the swipes use one: it observes the pointer without
          // entering the arena, so pinch-to-zoom still belongs to the viewer
          // while a single finger draws.
          if (_penMode)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onInkDown,
                onPointerMove: _onInkMove,
                onPointerUp: _onInkUp,
                onPointerCancel: (_) => _livePoints.value = const [],
                child: RepaintBoundary(
                  child: CustomPaint(
                    // The stroke being made right now, drawn in view
                    // coordinates: it repaints from the notifier without
                    // rebuilding the reader, and only becomes a stored,
                    // page-anchored mark when the pen lifts.
                    painter: _LiveStrokePainter(
                      points: _livePoints,
                      color: Color(_inkColor),
                      width: _inkWidth *
                          (_page == null ? 0 : _pageHeightOnScreen),
                    ),
                  ),
                ),
              ),
            ),
          // What is selected, and the ways to change it a drag cannot express.
          // Above the tool bar, because it is about the mark rather than about
          // the pen.
          if (_penMode && _ink.selected != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 74,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: InkSelectionBar(
                    isText: _ink.selected!.kind == InkTargetKind.text,
                    onSmaller: () => _changeSelectedText((text) =>
                        text.copyWith(
                            size: (text.size / inkTextSizeStep)
                                .clamp(minInkTextSize, maxInkTextSize)
                                .toDouble())),
                    onBigger: () => _changeSelectedText((text) => text.copyWith(
                        size: (text.size * inkTextSizeStep)
                            .clamp(minInkTextSize, maxInkTextSize)
                            .toDouble())),
                    onTurnLeft: () => _changeSelectedText((text) =>
                        text.copyWith(rotation: text.rotation - inkRotationStep)),
                    onTurnRight: () => _changeSelectedText((text) =>
                        text.copyWith(rotation: text.rotation + inkRotationStep)),
                    onEdit: _editSelectedText,
                    onDelete: _deleteSelected,
                  ),
                ),
              ),
            ),
          if (_penMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: InkToolbar(
                    tool: _tool,
                    color: _inkColor,
                    width: _inkWidth,
                    canUndo: _page != null && !_ink.markupOf(_page!).isEmpty,
                    onTool: (tool) => setState(() {
                      _tool = tool;
                      // A selection belongs to the select tool; leaving it with
                      // a box still drawn round something is a lie about what
                      // the next drag will do.
                      if (tool != InkTool.select) {
                        _ink.selected = null;
                        _ink.selectedPage = null;
                      }
                    }),
                    onColor: (color) => setState(() => _inkColor = color),
                    onWidth: (width) => setState(() => _inkWidth = width),
                    onUndo: _undoInk,
                    onDone: () => _setPenMode(false),
                  ),
                ),
              ),
            ),
          // What the toolbar would have said, now that the toolbar is gone:
          // where you are, how far through, how long is left. Reading mode
          // only — with the chrome up, the counter above says it already.
          if (_chromeHidden && _page != null && _pageCount != null)
            Positioned(
              left: 16,
              bottom: 12,
              child: IgnorePointer(
                child: Text(
                  readingModeStatus(
                    page: _page!,
                    count: _pageCount!,
                    pagesPerMinute: _pace,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: readerTheme.foreground.withValues(alpha: 0.55),
                  ),
                ),
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

/// The stroke under the pen right now.
///
/// Separate from [InkPainter], which draws what is *stored* on the page: this
/// one lives in view coordinates and repaints on every pointer move, which is
/// cheap precisely because it knows nothing about pages, matrices or the
/// database. The moment the pen lifts, the stroke moves to the other painter
/// and this one goes empty.
class _LiveStrokePainter extends CustomPainter {
  _LiveStrokePainter({
    required this.points,
    required this.color,
    required this.width,
  }) : super(repaint: points);

  /// Repainted from this directly, which is what keeps a moving pen off the
  /// widget tree.
  final ValueListenable<List<Offset>> points;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final points = this.points.value;
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width.clamp(0.5, 64.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    if (points.length == 1) {
      canvas.drawCircle(
          points.first, paint.strokeWidth / 2, Paint()..color = color);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiveStrokePainter old) =>
      old.points != points || old.color != color || old.width != width;
}

/// A mark being dragged: what it is, where the finger started, and the mark as
/// it was before the drag began.
///
/// The original is kept because every frame computes the new position from the
/// *start* of the gesture rather than from the last frame. Accumulating deltas
/// is how a dragged thing slowly drifts out from under the finger.
class _InkDrag {
  const _InkDrag({
    required this.target,
    required this.from,
    required this.matrix,
    this.stroke,
    this.text,
    this.handle = false,
  });

  final InkTarget target;

  /// Where the finger went down, page-relative.
  final Offset from;

  /// The view transform when it went down. Every frame of the drag converts
  /// through this one, so a two-finger zoom part-way through moves the page
  /// without moving the mark out from under the finger.
  final Matrix4 matrix;

  final InkStroke? stroke;
  final InkText? text;

  /// True when the drag started on the corner handle, which turns and resizes
  /// instead of moving.
  final bool handle;
}
