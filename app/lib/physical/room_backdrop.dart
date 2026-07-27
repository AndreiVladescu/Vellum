import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/library_repository.dart';
import 'room_measure.dart';

/// The room backdrop: picking the photo, and the two-point calibration dialog
/// (plan 5 #29).
///
/// A photo of the wall, traced over at true scale, is what turns the physical
/// view from a diagram into something recognisable as *your* room.
///
/// **App-local, permanently.** The published layout document (#47) is geometry
/// only, and a photo of someone's home is exactly the thing that must not ride
/// a share link — the redaction there is structural, and adding a backdrop to
/// the document would be the one change that breaks it.

const _uuid = Uuid();

/// Where backdrops live under the data dir, alongside `covers/` and `photos/`.
const backdropDirName = 'backdrops';

/// Picks an image and stores it as [environmentId]'s backdrop.
///
/// Copied into the data dir rather than referenced, for the same reason as
/// #51's condition photos: a picture picked from the camera roll can be deleted
/// from the roll tomorrow, and a backdrop that evaporates is worse than none.
///
/// Returns the stored relative path, or null if the user backed out.
Future<String?> addRoomBackdrop(
  BuildContext context,
  LibraryRepository repository,
  String environmentId,
) async {
  final XFile? shot;
  try {
    shot = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Bigger than a condition photo: this one is traced over, so detail at
      // the edges of the frame is the whole point. Still bounded — a 48 MP
      // original would be decoded on every room open for no benefit.
      maxWidth: 3000,
      maxHeight: 3000,
      imageQuality: 88,
    );
  } on Exception catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't get a photo: $e")));
    }
    return null;
  }
  if (shot == null) return null;

  final ext = p.extension(shot.path).replaceFirst('.', '').toLowerCase();
  final relative =
      p.join(backdropDirName, '${_uuid.v4()}.${ext.isEmpty ? 'jpg' : ext}');
  final dest = File(p.join(repository.dataDir.path, relative));
  await dest.parent.create(recursive: true);
  // `.part` then rename, like every other blob write: a row must never point at
  // a half-copied file, and the startup sweep already clears strays.
  final part = File('${dest.path}.part');
  try {
    await File(shot.path).copy(part.path);
    await part.rename(dest.path);
  } catch (e) {
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {
      // Best-effort; the sweep will get it.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't save the photo: $e")));
    }
    return null;
  }

  // The previous photo, so replacing one doesn't leak the old file.
  final previous =
      (await repository.layout.environment(environmentId))?.backdropPath;
  await repository.layout.updateBackdrop(
    environmentId,
    backdropPath: Value(relative),
    // A new photo invalidates the old calibration: the scale belonged to the
    // *previous* image's pixels, and keeping it would silently draw the room
    // at the wrong size.
    scale: const Value(null),
  );
  if (previous != null && previous != relative) {
    try {
      await File(p.join(repository.dataDir.path, previous)).delete();
    } catch (_) {
      // Already gone, or unreadable — the row is what mattered.
    }
  }
  return relative;
}

/// Removes a room's backdrop, photo and all.
Future<void> removeRoomBackdrop(
  LibraryRepository repository,
  String environmentId,
) async {
  final previous =
      (await repository.layout.environment(environmentId))?.backdropPath;
  await repository.layout.updateBackdrop(
    environmentId,
    backdropPath: const Value(null),
    scale: const Value(null),
  );
  if (previous == null) return;
  try {
    await File(p.join(repository.dataDir.path, previous)).delete();
  } catch (_) {
    // As above.
  }
}

/// Asks for the two-point calibration.
///
/// Phrased as "how far apart are these two points, and what is that really?"
/// — nobody knows their phone's focal length, but everybody can measure a door.
/// The pixel distance is entered rather than dragged because the canvas already
/// carries pan, zoom, drag-a-book and drag-a-shelf; a fifth gesture would need
/// a mode nobody would find.
class BackdropCalibrationDialog extends StatefulWidget {
  const BackdropCalibrationDialog({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
  });

  final int imageWidth;
  final int imageHeight;

  @override
  State<BackdropCalibrationDialog> createState() =>
      _BackdropCalibrationDialogState();
}

class _BackdropCalibrationDialogState extends State<BackdropCalibrationDialog> {
  // Pre-filled with the photo's full width and a plausible wall, so the common
  // case ("this whole photo is about three metres across") is two taps.
  late final _pixels =
      TextEditingController(text: widget.imageWidth.toString());
  final _metres = TextEditingController(text: '3.0');

  @override
  void dispose() {
    _pixels.dispose();
    _metres.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calibrate the photo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick something in the photo you can measure — a door, a shelf, '
              'the whole wall — then say how wide it is in the picture and how '
              'wide it really is.\n\n'
              'The photo is ${widget.imageWidth} × ${widget.imageHeight} pixels.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pixels,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'That length, in photo pixels',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _metres,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'What it really is, in metres',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            BackdropCalibration(
              pixelDistance: double.tryParse(_pixels.text.trim()) ?? 0,
              realMetres: double.tryParse(_metres.text.trim()) ?? 0,
            ),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// The opacity slider and "remove photo", as a small sheet.
class BackdropSettingsSheet extends StatelessWidget {
  const BackdropSettingsSheet({
    super.key,
    required this.repository,
    required this.environmentId,
    required this.opacity,
    required this.onChanged,
  });

  final LibraryRepository repository;
  final String environmentId;
  final double opacity;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room photo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('How strongly the photo shows through.'),
            Slider(
              value: opacity.clamp(0, 1),
              onChanged: (value) async {
                await repository.layout
                    .updateBackdrop(environmentId, opacity: value);
                onChanged();
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await removeRoomBackdrop(repository, environmentId);
                  onChanged();
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove photo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
