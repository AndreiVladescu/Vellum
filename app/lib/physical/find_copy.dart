import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../settings/app_settings.dart';
import 'environment_editor_page.dart';
import 'locate.dart';

/// *Find my copy* (plan 5 #28): the bridge from a book to the shelf it is
/// standing on.
///
/// The physical view was a map with no "you are here" — it could show you every
/// room but not answer the one question the feature exists for. This opens the
/// right room, points the camera at the book, and pulses it.
///
/// Three cases, all of which happen:
/// - **no placement** — say so plainly rather than opening an empty room;
/// - **one** — go straight there, no menu for a choice of one;
/// - **several** — ask which, naming the room and shelf, because a book with
///   two copies in two rooms is precisely when guessing is wrong.
Future<void> findMyCopy(
  BuildContext context,
  LibraryRepository repository,
  AppSettingsStore settings,
  Book book, {
  String? copyId,
}) async {
  var sightings = await repository.layout.sightingsOf(book.id);
  if (copyId != null) {
    sightings = [for (final s in sightings) if (s.copyId == copyId) s];
  }
  if (!context.mounted) return;

  if (sightings.isEmpty) {
    final l10n = L10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(copyId == null ? l10n.findCopyNoneBook : l10n.findCopyNoneCopy),
    ));
    return;
  }

  final chosen = sightings.length == 1
      ? sightings.single
      : await _pickSighting(context, sightings);
  if (chosen == null || !context.mounted) return;

  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => EnvironmentEditorPage(
      repository: repository,
      settings: settings,
      environmentId: chosen.environmentId,
      environmentName: chosen.environmentName,
      focusPlacementId: chosen.placementId,
    ),
  ));
}

Future<BookSighting?> _pickSighting(
  BuildContext context,
  List<BookSighting> sightings,
) =>
    showDialog<BookSighting>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(L10n.of(context).findCopyPlacedTitle(sightings.length)),
        children: [
          for (final sighting in sightings)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(sighting),
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(sighting.display),
              ),
            ),
        ],
      ),
    );
