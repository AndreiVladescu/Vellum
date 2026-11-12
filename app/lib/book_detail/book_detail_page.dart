import 'package:desktop_drop/desktop_drop.dart';
import '../widgets/page_insets.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/book_file_validation.dart';
import '../data/database.dart';
import '../shelf/author_page.dart';
import '../data/catalogue_enrich.dart';
import '../data/library_repository.dart';
import '../loans/borrow_requests.dart';
import '../physical/find_copy.dart';
import '../reader/annotations/annotations_panel.dart';
import '../server/connection_store.dart';
import '../server/write_access_request.dart';
import '../settings/app_settings.dart';
import '../snack_bars.dart';
import 'cover_thumb.dart';
import 'edit_book_sheet.dart';
import 'formats_section.dart';
import 'genres_section.dart';
import 'lend_sheet.dart';
import 'physical_copies_section.dart';
import 'read_button.dart';
import 'reader_notes_section.dart';
import 'reading_stats_section.dart';
import 'send_to_device_sheet.dart';
import '../data/shelf_service.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/labels.dart';

/// Full-page book view: metadata, digital formats, physical copies, and the
/// Read / Resume reading action.
class BookDetailPage extends StatelessWidget {
  const BookDetailPage({
    super.key,
    required this.book,
    required this.repository,
    this.settings,
    this.connection,
    this.onGenreTap,
  });

  /// Snapshot used before the first stream event arrives.
  final Book book;
  final LibraryRepository repository;

  /// Needed only to ask to borrow a book someone else owns (plan 5 #49).
  final ServerConnection? connection;

  /// Needed only to open the room editor for *Find my copy* (plan 5 #28); the
  /// action is hidden when a caller has no settings store to hand.
  final AppSettingsStore? settings;

  /// Tapping a genre chip closes this page and filters the shelf by that genre.
  final void Function(String genre)? onGenreTap;

  @override
  Widget build(BuildContext context) {
    // Watch the row so reading progress / edits update live.
    return StreamBuilder<Book?>(
      stream: repository.watchBook(book.id),
      initialData: book,
      builder: (context, snapshot) {
        final current = snapshot.data;
        if (current == null) {
          // Book was deleted while this page was open.
          return const Scaffold(body: SizedBox.shrink());
        }
        return _BookDetailBody(
          book: current,
          repository: repository,
          settings: settings,
          connection: connection,
          onGenreTap: onGenreTap,
        );
      },
    );
  }
}

class _BookDetailBody extends StatefulWidget {
  const _BookDetailBody({
    required this.book,
    required this.repository,
    this.settings,
    this.connection,
    this.onGenreTap,
  });

  final Book book;
  final LibraryRepository repository;
  final AppSettingsStore? settings;
  final ServerConnection? connection;
  final void Function(String genre)? onGenreTap;

  @override
  State<_BookDetailBody> createState() => _BookDetailBodyState();
}

class _BookDetailBodyState extends State<_BookDetailBody> {
  bool _dragging = false;

  Book get book => widget.book;
  LibraryRepository get repository => widget.repository;

  /// Whether to offer "Ask to borrow" (plan 5 #49). Needs a connected server
  /// that supports it; the server itself refuses a request for a book you own,
  /// which is the authoritative check — this only keeps the button honest.
  bool get _canRequestBorrow {
    final connection = widget.connection;
    return connection != null &&
        connection.isConnected &&
        (connection.capabilities?.hasFeature('borrow_requests') ?? false);
  }

  /// Handles files dropped anywhere on the page: images become the cover,
  /// PDFs/EPUBs are attached, anything else is rejected.
  Future<void> _handleDrop(List<XFile> files) async {
    final l10n = L10n.of(context);
    var attached = 0;
    var coverChanged = false;
    String? message;
    for (final file in files) {
      final kind = await classifyBookFile(file.path);
      if (kind == BookFileKind.image) {
        await repository.setCoverFromFile(book.id, file.path);
        coverChanged = true;
        message = l10n.detailCoverUpdated;
      } else if (kind.isBook) {
        await repository.attachFile(book.id, file.path);
        attached++;
      } else {
        message = l10n.detailOnlyPdfEpubImage;
      }
    }
    if (coverChanged) await _evictCover();
    if (attached > 0) {
      message = l10n.detailAttachedFiles(attached);
    }
    if (mounted && message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickCover() async {
    // Read before the awaits: the group name shows in the system file dialog.
    final l10n = L10n.of(context);
    final group = XTypeGroup(
      label: l10n.detailImagesTypeGroup,
      extensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp'],
    );
    final picked = await openFile(acceptedTypeGroups: [group]);
    if (picked == null) return;
    if (await classifyBookFile(picked.path) != BookFileKind.image) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.detailNotAnImage)),
        );
      }
      return;
    }
    await repository.setCoverFromFile(book.id, picked.path);
    await _evictCover();
  }

  /// The cover always writes to the same path, so drop it from the image cache
  /// to force a reload after a change.
  Future<void> _evictCover() async {
    final cover = repository.coverFileOf(book);
    if (cover != null) await FileImage(cover).evict();
    if (mounted) setState(() {});
  }

  Future<void> _coverFromFirstPage() async {
    final l10n = L10n.of(context);
    final ok = await repository.setCoverFromFirstPage(book.id);
    if (ok) await _evictCover();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l10n.detailCoverFromFirstPage
                : l10n.detailCoverNeedsPdf,
          ),
        ),
      );
    }
  }

  /// Flips the per-book sync opt-out, and says what that means — including the
  /// part people get wrong: excluding a book that has already been pushed does
  /// not recall it, because taking it off the server would remove it for
  /// everyone the library is shared with.
  Future<void> _toggleSync(Book book) async {
    final excluded = !book.syncExcluded;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    await repository.setSyncExcluded(book.id, excluded);
    if (!mounted) return;
    messenger.showSnackBar(
      appSnackBar(
        content: Text(excluded
            ? l10n.detailSyncOffSnack
            : l10n.detailSyncOnSnack),
      ),
    );
  }

  /// Asks the catalogues about this book — the only way a book with no file
  /// gets a cover, since there is no first page to take one from.
  Future<void> _lookUpOnline() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.detailLookingUp),
      duration: const Duration(seconds: 2),
    ));
    try {
      final outcome = await repository.enrich.fill(book);
      messenger.showSnackBar(SnackBar(
        content: Text(switch (outcome) {
          EnrichOutcome.filled => l10n.detailEnrichFilled,
          EnrichOutcome.alreadyComplete => l10n.detailEnrichComplete,
          EnrichOutcome.notFound => l10n.detailEnrichNotFound,
        }),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.detailLookupFailed('$e'))));
    }
  }

  void _openEditSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => EditBookSheet(
      book: book,
      repository: repository,
      onPickCover: _pickCover,
      onCoverFromFirstPage: _coverFromFirstPage,
      onLookUpOnline: _lookUpOnline,
    ),
  );

  /// The lend "mini menu": pick a physical copy to lend out or mark returned,
  /// without hunting through the page. See [LendSheet].
  void _openLendSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => LendSheet(book: book, repository: repository),
  );

  /// A sheet listing custom shelves with checkmarks; tapping one toggles this
  /// book's membership. Live via the shelves + membership streams.
  void _openShelfPicker() => showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: StreamBuilder<List<Shelf>>(
        stream: repository.watchShelves(),
        builder: (context, shelvesSnap) {
          // Same rule as the library's chip row: a shelf you declined is not
          // one you can add a book to.
          final settings = widget.settings;
          final shelves = [
            for (final s in shelvesSnap.data ?? const <Shelf>[])
              if (shelfIsShown(
                s,
                myUserId: widget.connection?.userId ?? '',
                acceptByDefault: settings?.acceptSharedShelves ?? true,
              ))
                s,
          ];
          return StreamBuilder<Set<String>>(
            stream: repository.watchShelfIdsFor(book.id),
            builder: (context, memberSnap) {
              final member = memberSnap.data ?? const <String>{};
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(L10n.of(context).detailAddToShelf),
                    ),
                  ),
                  if (shelves.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(L10n.of(context).detailNoShelvesYet),
                    ),
                  for (final shelf in shelves)
                    CheckboxListTile(
                      title: Text(shelf.name),
                      value: member.contains(shelf.id),
                      onChanged: (on) => (on ?? false)
                          ? repository.addToShelf(book.id, shelf.id)
                          : repository.removeFromShelf(book.id, shelf.id),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(L10n.of(context).detailNewShelfItem),
                    onTap: () async {
                      final name = await _promptNewShelfName();
                      if (name != null && name.isNotEmpty) {
                        final id = await repository.createShelf(name);
                        await repository.addToShelf(book.id, id);
                      }
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );

  Future<String?> _promptNewShelfName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).shelfNew),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              InputDecoration(hintText: L10n.of(context).shelfNameHint),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(L10n.of(context).create),
          ),
        ],
      ),
    );
  }

  Future<void> _revert() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(dialogContext).detailRevertTitle),
        content: Text(L10n.of(dialogContext).detailRevertBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L10n.of(dialogContext).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(L10n.of(dialogContext).detailRevertConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repository.revertToDefault(book);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).detailReverted)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final cover = repository.coverFileOf(book);
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        // The three sharing-related actions below are each conditional on
        // server/connection state, and used to sit unconditionally alongside
        // the five actions that are always shown — up to eight icons at once
        // on a book synced from a server you don't own. They now collapse
        // into one "More" button, the same fix the room editor's toolbar
        // just got: the icon count stops depending on how many of those
        // conditions happen to be true at once.
        actions: [
          if (widget.settings != null)
            IconButton(
              icon: const Icon(Icons.travel_explore_outlined),
              tooltip: l10n.detailFindMyCopy,
              onPressed: () => findMyCopy(
                context,
                repository,
                widget.settings!,
                book,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.handshake_outlined),
            tooltip: l10n.detailLendOrReturn,
            onPressed: _openLendSheet,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: l10n.detailAddToShelf,
            onPressed: _openShelfPicker,
          ),
          // Whether this book travels to the server, and the switch for it.
          // Shown whatever the connection state: it is a standing decision
          // about the book, and hiding it until you happen to be connected
          // would make it undiscoverable on the device you set up offline.
          IconButton(
            icon: Icon(book.syncExcluded
                ? Icons.cloud_off_outlined
                : Icons.cloud_done_outlined),
            tooltip: book.syncExcluded
                ? l10n.detailSyncOffTooltip
                : l10n.detailSyncOnTooltip,
            onPressed: () => _toggleSync(book),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.detailEditDetails,
            onPressed: _openEditSheet,
          ),
          if (_canRequestBorrow ||
              (widget.connection?.isConnected == true &&
                  book.addedBy != null) ||
              SendToDeviceSheet.availableOn(widget.connection))
            PopupMenuButton<String>(
              tooltip: l10n.detailMore,
              onSelected: (choice) {
                switch (choice) {
                  case 'borrow':
                    promptBorrowRequest(
                      context,
                      widget.connection!,
                      book.id,
                      book.title,
                      // Whoever added it is who owns it — the same name the
                      // page shows under "Added by".
                      owner: book.addedBy,
                    );
                  case 'edit-request':
                    promptWriteAccessRequest(
                      context,
                      widget.connection!,
                      book.id,
                      book.title,
                    );
                  case 'send':
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => SendToDeviceSheet(
                        book: book,
                        repository: repository,
                        connection: widget.connection!,
                      ),
                    );
                }
              },
              itemBuilder: (context) => [
                // Only for a book you don't own: asking to borrow your own
                // book is a button that can only produce an error.
                if (_canRequestBorrow)
                  PopupMenuItem(
                    value: 'borrow',
                    child: Text(l10n.detailAskToBorrow),
                  ),
                // Offered on a synced library only — `addedBy` is set by a
                // pull, so it is the app's one signal that this book came
                // from a server with an owner to ask. Whether *this* account
                // can already edit it is the server's to answer, and it
                // does, in a sentence.
                if (widget.connection?.isConnected == true &&
                    book.addedBy != null)
                  PopupMenuItem(
                    value: 'edit-request',
                    child: Text(l10n.detailAskToEdit),
                  ),
                // Only when the server has a mailer (plan 5 #53) — the file
                // and the outbound email both live there.
                if (SendToDeviceSheet.availableOn(widget.connection))
                  PopupMenuItem(
                    value: 'send',
                    child: Text(l10n.detailSendToDevice),
                  ),
              ],
            ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          _handleDrop(details.files);
        },
        child: Container(
          foregroundDecoration: _dragging
              ? BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                )
              : null,
          child: ListView(
            padding: pageInsets(context, EdgeInsets.all(24)),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverThumb(cover: cover, onTap: _pickCover),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.title, style: theme.textTheme.headlineSmall),
                        if (book.subtitle != null)
                          Text(
                            book.subtitle!,
                            style: theme.textTheme.titleMedium,
                          ),
                        const SizedBox(height: 8),
                        FutureBuilder<BookDetails>(
                          future: repository.detailsFor(book.id),
                          builder: (context, snapshot) {
                            final details = snapshot.data;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Authors are their own row so each name can
                                // be tapped through to everything else of
                                // theirs; the rest stays one plain line.
                                if (details != null &&
                                    details.authors.isNotEmpty)
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      for (final (i, name)
                                          in details.authors.indexed) ...[
                                        if (i > 0)
                                          Text(', ',
                                              style: theme.textTheme.bodyMedium),
                                        InkWell(
                                          onTap: () => Navigator.of(context)
                                              .push(MaterialPageRoute<void>(
                                            builder: (_) => AuthorPage(
                                              author: name,
                                              repository: repository,
                                              settings: widget.settings,
                                              connection: widget.connection,
                                            ),
                                          )),
                                          child: Text(
                                            name,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                Text(
                                  [
                                    if (book.publishedYear != null)
                                      '${book.publishedYear}',
                                    if (book.pageCount != null)
                                      l10n.detailPages(book.pageCount!),
                                    if (book.publisher != null) book.publisher!,
                                  ].join(' · '),
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if (book.isbn != null)
                                  Text(
                                    l10n.detailIsbn(book.isbn!),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                // Known only once a server has said so, so
                                // this is absent on a library that has never
                                // synced — where the answer would be "you" for
                                // every book anyway.
                                if (book.addedBy != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      l10n.detailAddedBy(book.addedBy!),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                GenresSection(
                                  repository: repository,
                                  bookId: book.id,
                                  onGenreTap: widget.onGenreTap,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ReadButton(book: book, repository: repository),
              if (book.description != null) ...[
                const SizedBox(height: 20),
                Text(l10n.detailAbout, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(book.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              DigitalFormatsSection(book: book, repository: repository),
              const SizedBox(height: 24),
              PhysicalCopiesSection(book: book, repository: repository),
              const SizedBox(height: 24),
              _SeriesStrip(book: book, repository: repository),
              _StatusAndRating(book: book, repository: repository),
              ReadingStatsSection(book: book, repository: repository),
              ReaderNotesSection(book: book, repository: repository),
              // The reading record for this book (plan 5 #22). No onJump here:
              // the detail page has nowhere to jump to, so entries are a record
              // rather than navigation — tapping one would promise a jump the
              // page can't make.
              StreamBuilder<List<Annotation>>(
                stream: repository.annotations.watchForBook(book.id),
                builder: (context, snapshot) {
                  final annotations = snapshot.data ?? const <Annotation>[];
                  if (annotations.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Three entries here, the rest behind a button: the
                        // detail page scrolls as a whole, and a fixed-height
                        // list inside it swallows the page's own scroll.
                        AnnotationsPanel(
                          book: book,
                          store: repository.annotations,
                          maxInline: 3,
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (repository.canRevert(book)) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _revert,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: Text(l10n.detailRevertButton),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () async {
                    // Capture both now: trashing the book makes the parent
                    // StreamBuilder emit null and unmount this widget, so
                    // `context` would no longer be mounted to pop or to show
                    // the undo snackbar with.
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(l10n.detailTrashTitle(book.title)),
                        content: Text(l10n.detailTrashBody(
                            TrashService.graceperiod.inDays)),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: Text(l10n.cancel),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                dialogContext,
                              ).colorScheme.error,
                            ),
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: Text(l10n.moveToTrash),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await repository.trashBook(book.id);
                    navigator.pop();
                    // The grace period makes an in-place undo cheap and
                    // honest: restoring is one column write, not a restore
                    // from backup.
                    messenger.showSnackBar(
                      appSnackBar(
                        content: Text(l10n.detailMovedToTrash(book.title)),
                        action: SnackBarAction(
                          label: l10n.undo,
                          onPressed: () => repository.restoreBook(book.id),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.moveToTrash),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Reading status and rating (plan 5 #18).
///
/// Both are the reader's own judgement, so both are one tap and neither is ever
/// set behind their back: the only automatic transition in the app is
/// unread → reading when a book is opened, and "finished" is *offered* near the
/// end rather than assumed (see [ReadingStatusService]).
class _StatusAndRating extends StatelessWidget {
  const _StatusAndRating({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final status = ReadingStatus.parse(book.status);
    final wanted = WishlistService.isWanted(book);
    final offerFinish =
        !wanted && ReadingStatusService.shouldOfferFinished(book);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PopupMenuButton<ReadingStatus>(
                tooltip: l10n.detailReadingStatus,
                onSelected: (choice) =>
                    repository.readingStatus.setStatus(book.id, choice),
                itemBuilder: (context) => [
                  // Owned states only; "wanted" is offered separately below,
                  // because it is about ownership rather than reading
                  // (plan 5 #21a).
                  for (final option in ReadingStatus.ownedStates)
                    PopupMenuItem(
                      value: option,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(option.labelOf(l10n)),
                        subtitle: Text(option.descriptionOf(l10n)),
                        trailing: option == status ? const Icon(Icons.check) : null,
                      ),
                    ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.bookmark_border, size: 18),
                  label: Text(status.labelOf(l10n)),
                ),
              ),
              const SizedBox(width: 12),
              // Five taps, not a slider: a rating is a choice among five, and a
              // slider invites precision the scale doesn't have.
              for (var star = 1; star <= 5; star++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.detailRatingStars(star),
                  icon: Icon(
                    (book.rating ?? 0) >= star ? Icons.star : Icons.star_border,
                    size: 20,
                  ),
                  // Tapping the current rating clears it — otherwise a
                  // mis-tapped rating can never be taken back.
                  onPressed: () => repository.readingStatus.setRating(
                    book.id,
                    book.rating == star ? null : star,
                  ),
                ),
            ],
          ),
          if (book.finishedAt != null)
            Text(
              book.readCount > 1
                  ? l10n.detailFinishedOnTimes(
                      book.finishedAt!.toLocal().toString().split(' ').first,
                      book.readCount)
                  : l10n.detailFinishedOn(
                      book.finishedAt!.toLocal().toString().split(' ').first),
              style: theme.textTheme.bodySmall,
            ),
          if (offerFinish)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.tonalIcon(
                onPressed: () => repository.readingStatus
                    .setStatus(book.id, ReadingStatus.finished),
                icon: const Icon(Icons.check),
                label: Text(l10n.detailMarkFinished),
              ),
            ),
          // A wanted book says so plainly, and offers the one transition that
          // matters (plan 5 #21a). Attaching a file or adding a copy does this
          // by itself — this is for the physical book you bought and haven't
          // catalogued yet.
          if (wanted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.detailWishlistNote,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.tertiary),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => repository.wishlist.markOwned(book.id),
                    icon: const Icon(Icons.library_add_check_outlined),
                    label: Text(l10n.detailIOwnThisNow),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


/// Where this book sits in its series, and what's missing (plan 5 #17).
///
/// The gap list is the most useful thing the feature can say: not "book 2 of 5"
/// but "you're missing 2". Tapping *Set series…* edits the membership; the field
/// autocompletes over series the library already knows, so a typo doesn't create
/// a second "Dune".
class _SeriesStrip extends StatefulWidget {
  const _SeriesStrip({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  State<_SeriesStrip> createState() => _SeriesStripState();
}

class _SeriesStripState extends State<_SeriesStrip> {
  /// Held in state, not recomputed in `build`: the gap list changes when a
  /// *sibling* is wished for or bought, which never touches this book's row —
  /// so nothing else would tell the strip to look again.
  late Future<SeriesPlace?> _place = _load();

  Book get book => widget.book;
  LibraryRepository get repository => widget.repository;

  Future<SeriesPlace?> _load() => repository.seriesService.placeOf(book);

  void _reload() => setState(() => _place = _load());

  Future<void> _edit(BuildContext context) async {
    final names = await repository.seriesService.watchNames().first;
    final current = await repository.seriesService.nameOf(book.id) ?? '';
    if (!context.mounted) return;
    final nameController = TextEditingController(text: current);
    final indexController = TextEditingController(
      text: book.seriesIndex == null
          ? ''
          // Trim a trailing .0 so "2" doesn't come back as "2.0".
          : (book.seriesIndex! % 1 == 0
              ? book.seriesIndex!.toInt().toString()
              : book.seriesIndex!.toString()),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(dialogContext).seriesEditTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: current),
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return names;
                return names
                    .where((n) => n.toLowerCase().contains(q))
                    .toList();
              },
              onSelected: (value) => nameController.text = value,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                controller.addListener(
                    () => nameController.text = controller.text);
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: L10n.of(context).seriesNameLabel,
                    helperText: L10n.of(context).seriesNameHelper,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: indexController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: L10n.of(dialogContext).seriesVolumeLabel,
                helperText: L10n.of(dialogContext).seriesVolumeHelper,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.of(dialogContext).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.of(dialogContext).save),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await repository.seriesService.setSeries(
      book.id,
      nameController.text,
      double.tryParse(indexController.text.trim()),
    );
    if (mounted) _reload();
  }

  /// Puts a missing volume on the wishlist, carrying this book's author across
  /// — a series is usually one author's, and typing it again is busywork.
  Future<void> _wishVolume(
    BuildContext context,
    SeriesPlace place,
    int volume,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    final details = await repository.detailsFor(book.id);
    await repository.wishlist.addSeriesGap(
      seriesName: place.name,
      volume: volume,
      author: details.authors.firstOrNull,
      title: l10n.wishlistGapTitle(place.name, volume),
      note: l10n.wishlistGapNote(volume, place.name),
    );
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.seriesVolumeWished(place.name, volume)),
    ));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return FutureBuilder<SeriesPlace?>(
      future: _place,
      builder: (context, snapshot) {
        final place = snapshot.data;
        if (place == null) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.format_list_numbered, size: 18),
              label: Text(l10n.seriesSet),
            ),
          );
        }
        final index = place.index;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      index == null
                          ? place.name
                          : l10n.seriesPosition(
                              place.name,
                              '${index % 1 == 0 ? index.toInt() : index}',
                              place.owned.length),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: l10n.seriesEditTooltip,
                    onPressed: () => _edit(context),
                  ),
                ],
              ),
              if (place.hasGaps) ...[
                Text(
                  l10n.seriesMissingVolumes(place.gaps.join(', ')),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.tertiary),
                ),
                // The gap list's natural next question — "so get it" — answered
                // where it's asked (plan 5 #17 feeding #21a). Volumes already
                // wished for drop out of `openGaps`, so tapping one doesn't
                // leave a chip that would add a duplicate.
                if (place.openGaps.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final volume in place.openGaps)
                        ActionChip(
                          avatar: const Icon(Icons.bookmark_add_outlined,
                              size: 16),
                          label: Text(l10n.seriesWantVolume(volume)),
                          onPressed: () => _wishVolume(context, place, volume),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
