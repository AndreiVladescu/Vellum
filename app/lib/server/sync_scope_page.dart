import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../settings/app_settings.dart';
import '../snack_bars.dart';
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

  /// Turning a switch off stops the resource syncing from now on — it says
  /// nothing about what is already up there. Unticking a box about your lending
  /// history and leaving that history on the server is not what anyone means,
  /// so the offer is made at the moment it is relevant rather than left to be
  /// found later.
  ///
  /// Asked, never assumed: someone may be switching a resource off *because*
  /// the server's copy is the good one.
  Future<void> _offerToForget(String resource, String label) async {
    final client = widget.connection.client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Also remove $label from the server?'),
        content: Text(
          'Switching this off stops $label syncing from now on. What you have '
          'already sent stays on the server unless you remove it here.\n\n'
          'This removes only yours — nothing belonging to anyone you share the '
          'library with — and it cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Leave it there'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove from server'),
          ),
        ],
      ),
    );
    if (go != true) return;
    try {
      final removed = await client.forgetMine(resource);
      messenger.showSnackBar(appSnackBar(
        content: Text('Removed $removed from the server.'),
      ));
    } catch (e) {
      messenger.showSnackBar(
        appSnackBar(content: Text('Could not remove $label: $e')),
      );
    }
  }

  /// A switch that offers to un-publish when it goes off.
  Future<void> _setAndOffer(
    SyncScope next,
    bool value, {
    required String resource,
    required String label,
  }) async {
    await _set(next);
    if (!value && mounted) await _offerToForget(resource, label);
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
            onChanged: (v) => _setAndOffer(
              _scope.copyWith(copies: v),
              v,
              resource: 'copies',
              label: 'physical copies',
            ),
          ),
          _row(
            title: 'Loans',
            subtitle: 'Who has what, and the history of who had it',
            value: _scope.loans,
            onChanged: (v) => _setAndOffer(
              _scope.copyWith(loans: v),
              v,
              resource: 'loans',
              label: 'loans',
            ),
          ),
          _row(
            title: 'Copy photos',
            subtitle: 'Pictures of your shelves — the heaviest thing here',
            value: _scope.copyPhotos,
            onChanged: (v) => _setAndOffer(
              _scope.copyWith(copyPhotos: v),
              v,
              resource: 'copy-photos',
              label: 'copy photos',
            ),
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
            onChanged: (v) => _setAndOffer(
              _scope.copyWith(annotations: v),
              v,
              resource: 'annotations',
              label: 'highlights and notes',
            ),
          ),
          _row(
            title: 'Reading sittings',
            subtitle: 'When you read, and for how long',
            value: _scope.sessions,
            onChanged: (v) => _setAndOffer(
              _scope.copyWith(sessions: v),
              v,
              resource: 'sessions',
              label: 'reading sittings',
            ),
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
              // Books are the exception, and it is deliberate: "un-publish my
              // catalogue" is a different act from "stop syncing it", and it
              // already has its own front door in the console.
              'Switching something off offers to remove what you have already '
              'sent. Your books are the exception — deleting those from the '
              'server is done from the console, on purpose.',
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
