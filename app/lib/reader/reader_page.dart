import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../shortcuts.dart';
import 'annotations/annotation_locator.dart';
import 'annotations/annotations_panel.dart';
import 'annotations/highlight_palette.dart';
import 'annotations/pdf_highlight_painter.dart';
import 'night_mode.dart';
import 'edge_turn.dart';
import 'reader_hotkeys.dart';
import 'pdf_paged_view.dart';
import 'reader_settings.dart';
import 'reader_settings_sheet.dart';
import 'translate/translate_sheet.dart';
import 'translate/translation_backend.dart';

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

class _ReaderPageState extends State<ReaderPage> {
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
  );

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

  @override
  void dispose() {
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
      await _controller.goToPage(
        pageNumber: page,
        anchor: _settings?.pdfFit == PdfFit.page
            ? PdfPageAnchor.all
            : PdfPageAnchor.topCenter,
      );
    } finally {
      _navigating = false;
    }
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
  Future<void> _translateSelection() async {
    final settings = _settings;
    final ranges = _selectedRanges;
    if (settings == null || !settings.canTranslate) return;
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
        backend: LibreTranslateBackend(
          baseUrl: settings.translateUrl,
          apiKey: settings.translateApiKey,
        ),
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
            TextButton(
              onPressed: _promptPageJump,
              style: TextButton.styleFrom(
                foregroundColor: readerTheme.foreground,
              ),
              child: Text('$_page / $_pageCount'),
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
            // Only with a translation server configured: a button that can
            // only fail is worse than no button, the same rule the app follows
            // for "Forgot password?" and "Send to a device".
            if (settings?.canTranslate ?? false)
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
          GestureDetector(
            onTap: settings?.immersive == true
                ? () => setState(() => _chromeHidden = !_chromeHidden)
                : null,
            child: nightModeWrap(
              enabled: dark,
              child: PdfViewer.file(
        widget.file.path,
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
          viewerOverlayBuilder: _mode == PdfPageMode.scroll
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
          normalizeMatrix: _mode == PdfPageMode.paged ? _clamp : null,
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
              // Only rebuild when the *presence* of a selection changes: this
              // fires continuously while dragging.
              final had = _hasSelection;
              _selectedRanges = ranges;
              if (ranges.isNotEmpty != had) setState(() {});
            },
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
