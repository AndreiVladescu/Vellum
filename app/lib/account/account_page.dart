import 'package:file_selector/file_selector.dart';
import '../widgets/adaptive.dart';
import 'package:flutter/material.dart';
import '../l10n/gen/app_localizations.dart';

import '../snack_bars.dart';
import 'avatar_image.dart';
import 'profile_avatar.dart';
import 'user_profile.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.profile});

  final UserProfileStore profile;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _email = TextEditingController(text: widget.profile.email);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Picks a photo, scales it down and stores it.
  ///
  /// The picker is filtered to images, which is a hint rather than a guarantee
  /// — a text file renamed to `.png` gets through it — so the failure is caught
  /// and said out loud instead of leaving a blank circle.
  Future<void> _pickPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    final picked = await openFile(acceptedTypeGroups: [
      XTypeGroup(
        label: L10n.of(context).detailImagesTypeGroup,
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
      ),
    ]);
    if (picked == null) return;
    try {
      await widget.profile.setPhoto(await picked.readAsBytes());
    } on AvatarImageException catch (e) {
      messenger.showSnackBar(appSnackBar(content: Text(e.messageOf(l10n))));
    } catch (e) {
      messenger.showSnackBar(
        appSnackBar(content: Text(l10n.accountPhotoSaveFailedSnack('$e'))),
      );
    }
  }

  Future<void> _removePhoto() => widget.profile.clearPhoto();

  Future<void> _save() async {
    await widget.profile.save(name: _name.text, email: _email.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).accountSavedSnack)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.drawerAccount)),
      body: ListView(
        padding: readableInsets(context, EdgeInsets.all(24)),
        children: [
          // Listens rather than relying on setState: the photo can change from
          // the drawer as well, and a page that only repaints its own edits
          // shows a stale avatar the moment anything else touches the profile.
          ListenableBuilder(
            listenable: widget.profile,
            builder: (context, _) => Center(
            child: Column(
              children: [
                // The photo is the button. A separate "change photo" control
                // beside it would be a second thing to explain.
                Tooltip(
                  message: widget.profile.photoPath == null
                      ? l10n.accountAddPhotoTooltip
                      : l10n.accountChangePhotoTooltip,
                  child: InkWell(
                    onTap: widget.profile.canSetPhoto ? _pickPhoto : null,
                    customBorder: const CircleBorder(),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        ProfileAvatar(profile: widget.profile, radius: 44),
                        if (widget.profile.canSetPhoto)
                          CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(
                              Icons.photo_camera_outlined,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.profile.photoPath != null)
                  TextButton.icon(
                    onPressed: _removePhoto,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(l10n.accountRemovePhoto),
                  ),
              ],
            ),
          ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l10n.accountNameLabel,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l10n.accountEmailLabel,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(l10n.save)),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.accountLocalOnlyNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
