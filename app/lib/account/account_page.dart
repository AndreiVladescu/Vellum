import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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
    final picked = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
      ),
    ]);
    if (picked == null) return;
    try {
      await widget.profile.setPhoto(await picked.readAsBytes());
    } on AvatarImageException catch (e) {
      messenger.showSnackBar(appSnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        appSnackBar(content: Text("That photo couldn't be saved: $e")),
      );
    }
  }

  Future<void> _removePhoto() => widget.profile.clearPhoto();

  Future<void> _save() async {
    await widget.profile.save(name: _name.text, email: _email.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Profile saved')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(24),
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
                      ? 'Add a photo'
                      : 'Change photo',
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
                    label: const Text('Remove photo'),
                  ),
              ],
            ),
          ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Your profile is stored on this device only. When Vellum '
                'gains server sync, this will become the account you sign '
                'in with to reach a shared library.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
