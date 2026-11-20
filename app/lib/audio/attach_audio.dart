import 'package:material_ui/material_ui.dart';

import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import 'audio_formats.dart';
import 'audiobook_import.dart';

/// Attaches picked or dropped audio files to an existing book as its
/// audiobook, from the book's own page (docs/AUDIOBOOKS.md §3).
///
/// A book has one audio edition in 1.5, so a book that already has audio is
/// asked first whether to replace it. Says what happened in a snack bar.
Future<void> attachAudioToBook(
  BuildContext context, {
  required LibraryRepository repository,
  required String bookId,
  required List<String> paths,
}) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final importer = AudiobookImporter(repository);
  final usable = [
    for (final path in paths)
      if (await isImportableAudio(path)) path,
  ];
  if (usable.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.audioNotReadable)));
    return;
  }
  var replace = false;
  if (await importer.hasAudio(bookId)) {
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l = L10n.of(dialogContext);
        return AlertDialog(
          title: Text(l.audioReplaceTitle),
          content: Text(l.audioReplaceBody(usable.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l.audioReplaceAction),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    replace = true;
  }
  try {
    final scan = await importer.scan(usable);
    await importer.attachTo(bookId, scan, replace: replace);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.audioAttached(scan.parts.length))),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.audioImportFailed('$e'))));
  }
}

/// "5:12:33" or "42:07": a length or position for an audiobook.
String formatAudioTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
