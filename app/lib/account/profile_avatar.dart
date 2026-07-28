import 'dart:io';

import 'package:flutter/material.dart';

import 'user_profile.dart';

/// The profile photo, or the initial if there isn't one.
///
/// One widget for both places it appears — the drawer header and the Account
/// page — so a photo can't show up in one and an initial in the other.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.radius = 20,
  });

  final UserProfileStore profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = profile.photoPath;
    return CircleAvatar(
      radius: radius,
      // Keyed by path so replacing the photo replaces what's on screen. The
      // file is written under a new name each time for the same reason.
      foregroundImage: path == null ? null : FileImage(File(path)),
      // Shown while the image loads and if it fails to decode — a corrupt file
      // then looks like no photo rather than like a broken app.
      child: Text(
        profile.initial,
        style: TextStyle(fontSize: radius * 0.8),
      ),
    );
  }
}
