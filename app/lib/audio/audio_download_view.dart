import 'package:material_ui/material_ui.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/formats.dart';
import '../l10n/gen/app_localizations.dart';
import 'audio_downloads.dart';
import 'audio_formats.dart';
import 'playback_host.dart';

/// One book's audio download, as a few lines and a button (docs/AUDIOBOOKS.md
/// §6): "Not downloaded to this device · 430 MB" and Download; a progress bar
/// and Cancel while it runs; the mobile-data question; what went wrong; and,
/// with [showWhenHere], "On this device" and Remove download.
///
/// The book page shows it under the audiobook in the formats list, the player
/// at the top of its page. Both watch the same [AudioDownloads], so a download
/// started in one is the same download in the other.
class AudioDownloadPanel extends StatefulWidget {
  AudioDownloadPanel({
    super.key,
    required this.bookId,
    required this.repository,
    this.showWhenHere = false,
    this.firstFileId,
    AudioDownloads? downloads,
    PlaybackHost? host,
  })  : downloads = downloads ?? AudioDownloads.instance,
        host = host ?? PlaybackHost.instance;

  final String bookId;
  final LibraryRepository repository;

  /// Whether to show anything once all the audio is here (the book page,
  /// where Remove download lives); the player has nothing to say then.
  final bool showWhenHere;

  /// The part to fetch first, when the player knows which one it needs.
  final String? Function()? firstFileId;
  final AudioDownloads downloads;
  final PlaybackHost host;

  @override
  State<AudioDownloadPanel> createState() => _AudioDownloadPanelState();
}

class _AudioDownloadPanelState extends State<AudioDownloadPanel> {
  // Made once, not in build: the player page rebuilds on every position tick,
  // and a new drift stream each time would churn its subscription.
  late final Stream<List<BookFile>> _files =
      widget.repository.watchFilesOf(widget.bookId);

  String get bookId => widget.bookId;
  LibraryRepository get repository => widget.repository;
  AudioDownloads get downloads => widget.downloads;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookFile>>(
      stream: _files,
      builder: (context, snapshot) {
        final parts = [
          for (final f in snapshot.data ?? const <BookFile>[])
            if (isAudioFormat(f.format)) f,
        ];
        if (parts.isEmpty) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: downloads,
          builder: (context, _) => _content(context, parts),
        );
      },
    );
  }

  Widget _content(BuildContext context, List<BookFile> parts) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final total = parts.fold<int>(0, (n, f) => n + f.sizeBytes);
    final here = parts.fold<int>(0, (n, f) => f.present ? n + f.sizeBytes : n);
    final allHere = parts.every((f) => f.present);
    final status = downloads.statusOf(bookId);
    final small = theme.textTheme.bodySmall;

    Future<void> start({bool anyway = false}) async {
      await downloads.download(repository, bookId,
          firstFileId: widget.firstFileId?.call(), allowMetered: anyway);
    }

    Widget line(String text, List<Widget> actions, {Widget? below}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: small),
              ?below,
              if (actions.isNotEmpty)
                Wrap(spacing: 8, children: actions),
            ],
          ),
        );

    switch (status?.phase) {
      case AudioDownloadPhase.downloading:
        return line(
          l10n.audioDownloadProgress(
            (status!.partsDone + 1).clamp(1, status.partsTotal),
            status.partsTotal,
            l10n.formatFileSize(status.receivedBytes),
            l10n.formatFileSize(status.totalBytes),
          ),
          [
            TextButton(
              onPressed: () => downloads.cancel(bookId),
              child: Text(l10n.audioDownloadCancel),
            ),
          ],
          below: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(value: status.fraction),
          ),
        );
      case AudioDownloadPhase.needsConsent:
        return line(l10n.audioDownloadMetered, [
          FilledButton.tonal(
            onPressed: () => start(anyway: true),
            child: Text(l10n.audioDownloadAnyway(l10n.formatFileSize(total - here))),
          ),
          TextButton(
            onPressed: () => downloads.dismiss(bookId),
            child: Text(l10n.audioDownloadCancel),
          ),
        ]);
      case AudioDownloadPhase.failed:
        final text = switch (status!.failure) {
          AudioDownloadFailure.noServer => l10n.audioDownloadNoServer,
          AudioDownloadFailure.hashMismatch => l10n.audioDownloadFailedHash,
          _ => l10n.audioDownloadFailedNetwork(status.detail ?? ''),
        };
        return line(text, [
          if (status.failure != AudioDownloadFailure.noServer)
            TextButton(
              onPressed: start,
              child: Text(l10n.audioDownloadRetry),
            ),
        ]);
      case null:
        break;
    }

    final remove = TextButton(
      onPressed: () => confirmRemoveAudioDownload(
        context,
        repository: repository,
        bookId: bookId,
        size: here,
        downloads: downloads,
        host: widget.host,
      ),
      child: Text(l10n.audioDownloadRemove),
    );
    if (allHere) {
      if (!widget.showWhenHere) return const SizedBox.shrink();
      return line(l10n.audioDownloadHere(l10n.formatFileSize(total)), [remove]);
    }
    return line(
      here == 0
          ? l10n.audioDownloadNotHere(l10n.formatFileSize(total))
          : l10n.audioDownloadPartlyHere(l10n.formatFileSize(here), l10n.formatFileSize(total)),
      [
        FilledButton.tonalIcon(
          onPressed: start,
          icon: const Icon(Icons.download),
          label: Text(l10n.audioDownloadButton),
        ),
        if (here > 0 && widget.showWhenHere) remove,
      ],
    );
  }
}

/// Asks, then frees the space [bookId]'s audio takes on this device. Stops
/// the book first if it is the one playing. The book itself stays, and so
/// does the audio on the server; nothing is removed if the server does not
/// hold every part (see [AudioDownloads.remove]). True once removed.
Future<bool> confirmRemoveAudioDownload(
  BuildContext context, {
  required LibraryRepository repository,
  required String bookId,
  required int size,
  AudioDownloads? downloads,
  PlaybackHost? host,
}) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.audioRemoveTitle),
      content: Text(l10n.audioRemoveBody(l10n.formatFileSize(size))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.audioDownloadCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.audioRemoveConfirm),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final playing = host ?? PlaybackHost.instance;
  if (playing.bookId == bookId) await playing.close();
  final result =
      await (downloads ?? AudioDownloads.instance).remove(repository, bookId);
  messenger.showSnackBar(SnackBar(
    content: Text(result == AudioRemoveResult.removed
        ? l10n.audioRemoved
        : l10n.audioRemoveNotOnServer),
  ));
  return result == AudioRemoveResult.removed;
}
