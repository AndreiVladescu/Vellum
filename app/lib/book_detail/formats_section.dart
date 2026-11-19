import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../audio/attach_audio.dart';
import '../audio/audio_download_view.dart';
import '../audio/audio_formats.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/formats.dart';
import '../l10n/gen/app_localizations.dart';

/// The "Digital formats" list: attached PDF/EPUB files plus an attach action.
class DigitalFormatsSection extends StatelessWidget {
  const DigitalFormatsSection({
    super.key,
    required this.book,
    required this.repository,
  });

  final Book book;
  final LibraryRepository repository;

  Future<void> _attach(BuildContext context) async {
    // Read before the await: the group name shows in the system file dialog.
    final l10n = L10n.of(context);
    final typeGroup = XTypeGroup(
      label: l10n.bookFilesTypeGroup,
      extensions: const ['pdf', 'epub', ...audioFormats],
    );
    // Several at once, for a folder of mp3s: they become one audiobook.
    final picked = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (picked.isEmpty || !context.mounted) return;
    final audio = [
      for (final f in picked)
        if (isAudioFormat(extensionOf(f.path))) f.path,
    ];
    final text = [
      for (final f in picked)
        if (!isAudioFormat(extensionOf(f.path))) f,
    ];
    for (final f in text) {
      await repository.attachFile(book.id, f.path);
    }
    if (text.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.formatsAttached(text.first.name))));
    }
    if (audio.isNotEmpty && context.mounted) {
      await attachAudioToBook(context,
          repository: repository, bookId: book.id, paths: audio);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return StreamBuilder<List<BookFile>>(
      stream: repository.watchFilesOf(book.id),
      builder: (context, snapshot) {
        final files = snapshot.data ?? const <BookFile>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A Wrap rather than a Row: when the heading and the button do not
            // fit side by side (long labels, large text) the button drops to
            // its own line instead of overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.formatsTitle,
                  style: theme.textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: () => _attach(context),
                  icon: const Icon(Icons.attach_file),
                  label: Text(l10n.formatsAttachFile),
                ),
              ],
            ),
            if (files.isEmpty)
              Text(
                l10n.formatsEmpty,
                style: theme.textTheme.bodySmall,
              )
            else ...[
              for (final f in files)
                if (!isAudioFormat(f.format))
                  ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    f.format == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.book_outlined,
                  ),
                  title: Text(f.format.toUpperCase()),
                  subtitle: Text(
                    l10n.formatFileSize(f.sizeBytes),
                  ),
                ),
              // An audiobook is one row however many parts it has.
              if (files.any((f) => isAudioFormat(f.format)))
                _audiobookTile(l10n, files),
            ],
          ],
        );
      },
    );
  }

  Widget _audiobookTile(L10n l10n, List<BookFile> files) {
    final parts = [for (final f in files) if (isAudioFormat(f.format)) f];
    final ms = parts.fold<int>(0, (sum, f) => sum + (f.durationMs ?? 0));
    final bytes = parts.fold<int>(0, (sum, f) => sum + f.sizeBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.headphones_outlined),
          title: Text(l10n.formatsAudiobook),
          subtitle: Text(l10n.formatsAudiobookDetail(
            parts.length,
            formatAudioTime(Duration(milliseconds: ms)),
            l10n.formatDecimal(bytes / (1024 * 1024)),
          )),
        ),
        // Audio comes on demand (docs/AUDIOBOOKS.md §6): whether it is here,
        // Download or its progress, and Remove download.
        Padding(
          padding: const EdgeInsets.only(left: 56),
          child: AudioDownloadPanel(
            bookId: book.id,
            repository: repository,
            showWhenHere: true,
          ),
        ),
      ],
    );
  }
}
