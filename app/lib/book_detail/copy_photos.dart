import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

/// Condition photos for a physical copy (plan 5 #51): the picker, a thumbnail
/// strip, and a full-size viewer.
///
/// `image_picker` is used rather than `file_selector` (which the rest of the app
/// uses for books) because on Android it reaches the camera, which is the whole
/// point here — you photograph a book as it goes out. Its desktop
/// implementations fall back to a file dialog, so the same call works
/// everywhere; only the *camera* option is hidden where there is no camera.
bool get _hasCamera => Platform.isAndroid || Platform.isIOS;

/// Picks an image and copies it into the library store, returning its new row
/// id, or null if the user backed out.
///
/// Downscaled to 2000px on the long edge: a modern phone photo is ~4 MB and
/// these ride every backup, while what the picture has to prove — a torn
/// jacket, a cracked spine — survives the resize easily.
Future<String?> captureCopyPhoto(
  BuildContext context,
  LibraryRepository repository,
  String copyId, {
  required ImageSource source,
  String? caption,
}) async {
  final XFile? shot;
  try {
    shot = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
  } on Exception catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't get a photo: $e")),
      );
    }
    return null;
  }
  if (shot == null) return null;
  return repository.copyPhotos.addPhoto(copyId, shot.path, caption: caption);
}

/// Offers camera-or-gallery where both exist, and goes straight to the file
/// dialog where only one does — a menu with a single item is just a click tax.
Future<String?> addCopyPhoto(
  BuildContext context,
  LibraryRepository repository,
  String copyId, {
  String? caption,
}) async {
  if (!_hasCamera) {
    return captureCopyPhoto(context, repository, copyId,
        source: ImageSource.gallery, caption: caption);
  }
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose an existing one'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  return captureCopyPhoto(context, repository, copyId,
      source: source, caption: caption);
}

/// The horizontal strip of a copy's condition photos, with an "add" tile.
///
/// Hidden entirely when a copy has no photos *and* [alwaysShow] is false, so a
/// library that never uses the feature doesn't grow a permanent empty shelf of
/// UI.
class CopyPhotoStrip extends StatelessWidget {
  const CopyPhotoStrip({
    super.key,
    required this.copyId,
    required this.repository,
    this.alwaysShow = false,
  });

  final String copyId;
  final LibraryRepository repository;
  final bool alwaysShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<CopyPhoto>>(
      stream: repository.copyPhotos.watchPhotosOf(copyId),
      builder: (context, snapshot) {
        final photos = snapshot.data ?? const <CopyPhoto>[];
        if (photos.isEmpty && !alwaysShow) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                photos.isEmpty
                    ? 'Condition photos'
                    : 'Condition photos (${photos.length})',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final photo in photos)
                      _PhotoThumb(
                        photo: photo,
                        repository: repository,
                      ),
                    _AddPhotoTile(
                      onTap: () =>
                          addCopyPhoto(context, repository, copyId),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text('Add', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.repository});

  final CopyPhoto photo;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    final file = repository.copyPhotos.fileOf(photo);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: photo.caption ?? _stamp(photo.takenAt),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: 88,
              height: 88,
              fit: BoxFit.cover,
              // A missing blob (restored backup, manual tidy-up) shows a
              // placeholder rather than a red error box.
              errorBuilder: (context, _, _) => Container(
                width: 88,
                height: 88,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: Image.file(repository.copyPhotos.fileOf(photo)),
              ),
            ),
            ListTile(
              title: Text(photo.caption ?? 'No caption'),
              subtitle: Text(_stamp(photo.takenAt)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Caption',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final text = await _promptCaption(
                          dialogContext, photo.caption);
                      if (text == null) return;
                      await repository.copyPhotos.setCaption(photo.id, text);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await repository.copyPhotos.deletePhoto(photo.id);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptCaption(BuildContext context, String? initial) async {
  final controller = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Caption'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'e.g. tear on the dust jacket',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

String _stamp(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
