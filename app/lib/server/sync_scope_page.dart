import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../settings/app_settings.dart';
import 'connection_store.dart';
import 'sync_scope.dart';

/// Choosing what a sync carries (next features #8).
///
/// Reached from *Library server*. Before this, sync was all-or-nothing per
/// pass: one press moved books, covers, files, shelves, copies, loans, copy
/// photos and everyone's marks, and the only opt-out was reading position,
/// which had its own switch because it is per-device rather than per-library.
///
/// Every switch here turns its resource off **in both directions**. That is not
/// a detail: a resource that stopped pushing but kept pulling would look like
/// it was still syncing, and one that stopped pulling but kept pushing would
/// quietly publish exactly what you asked it not to.
class SyncScopePage extends StatefulWidget {
  const SyncScopePage({
    super.key,
    required this.settings,
    required this.repository,
    required this.connection,
  });

  final AppSettingsStore settings;
  final LibraryRepository repository;
  final ServerConnection connection;

  @override
  State<SyncScopePage> createState() => _SyncScopePageState();
}

class _SyncScopePageState extends State<SyncScopePage> {
  late SyncScope _scope = widget.settings.syncScope;

  Future<void> _set(SyncScope next) async {
    setState(() => _scope = next);
    await widget.settings.setSyncScope(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('What syncs')),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Anything switched off is left alone in both directions — not '
              'sent to the server, and not fetched from it.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const Divider(height: 24),
          _row(
            title: 'Books, covers and files',
            subtitle: 'The catalogue itself, and the shelves it sits on',
            value: _scope.books,
            onChanged: (v) => _set(_scope.copyWith(books: v)),
          ),
          _row(
            title: 'Physical copies',
            subtitle: 'Which books you own as objects, and where they live',
            value: _scope.copies,
            onChanged: (v) => _set(_scope.copyWith(copies: v)),
          ),
          _row(
            title: 'Loans',
            subtitle: 'Who has what, and the history of who had it',
            value: _scope.loans,
            onChanged: (v) => _set(_scope.copyWith(loans: v)),
          ),
          _row(
            title: 'Copy photos',
            subtitle: 'Pictures of your shelves — the heaviest thing here',
            value: _scope.copyPhotos,
            onChanged: (v) => _set(_scope.copyWith(copyPhotos: v)),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Personal — kept per account, so a shared library holds several '
              'people’s marks in the same book without anyone seeing the '
              'others’.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          _row(
            title: 'Highlights, notes and bookmarks',
            subtitle: 'Everything you mark in a book, and your private notes',
            value: _scope.annotations,
            onChanged: (v) => _set(_scope.copyWith(annotations: v)),
          ),
          _row(
            title: 'Reading sittings',
            subtitle: 'When you read, and for how long',
            value: _scope.sessions,
            onChanged: (v) => _set(_scope.copyWith(sessions: v)),
          ),
          SwitchListTile(
            title: const Text('Reading position'),
            subtitle: const Text(
              'Where you stopped, per device. Has its own switch because it is '
              'the one thing here that is about a device rather than a library.',
            ),
            value: widget.settings.syncReadingPosition,
            onChanged: (v) async {
              await widget.settings.setSyncReadingPosition(v);
              if (mounted) setState(() {});
            },
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              // Said rather than left to be discovered: switching something off
              // stops it moving from now on, and does not reach back for what
              // is already on the server. Un-publishing needs endpoints that
              // only reading position has today.
              'Switching something off stops it syncing from now on. Anything '
              'already on the server stays there — the only one that can '
              'un-publish itself is reading position.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      );
}
