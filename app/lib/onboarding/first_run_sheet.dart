import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../l10n/gen/app_localizations.dart';

/// What the user chose to do from the first-run flow, so the caller can navigate.
/// The flow itself opens nothing — it only reports, which keeps it free of every
/// screen it points at.
enum FirstRunAction {
  importFolder,
  scan,
  addOne,
  trySamples,
  connectServer,
  createRoom,
}

/// The first-run introduction (plan 5 #41).
///
/// A new install is an empty shelf and one FAB, which says nothing about the four
/// things that make Vellum worth having. This is three cards over that gap:
/// getting books in, connecting a server, and building a room.
///
/// Deliberately **not** modal-blocking: it's a bottom sheet the user can dismiss
/// by swiping, every card is skippable, and it is marked seen the moment it opens
/// so a dismissal — however it happens — is never punished by it coming back.
class FirstRunSheet extends StatefulWidget {
  const FirstRunSheet({super.key});

  /// Shows the sheet if this install hasn't seen it, and returns the chosen
  /// action (or null if it was skipped or already seen).
  ///
  /// Marking it seen *before* awaiting the result is on purpose: a user who
  /// swipes it away has answered the question, and asking again next launch
  /// would be nagging.
  static Future<FirstRunAction?> maybeShow(
    BuildContext context,
    AppSettingsStore settings,
  ) async {
    if (settings.hasSeenFirstRun) return null;
    await settings.setHasSeenFirstRun(true);
    if (!context.mounted) return null;
    return showModalBottomSheet<FirstRunAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FirstRunSheet(),
    );
  }

  @override
  State<FirstRunSheet> createState() => _FirstRunSheetState();
}

class _FirstRunSheetState extends State<FirstRunSheet> {
  int _card = 0;

  static const _cards = 3;

  void _next() {
    if (_card < _cards - 1) {
      setState(() => _card++);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        // Scrollable, because at large text scales three paragraphs and a row of
        // buttons are taller than the sheet (caught by
        // test/widgets/large_text_test.dart). `isScrollControlled: true` on the
        // showModalBottomSheet call is what lets it use the room.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(l10n.firstRunWelcome, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              l10n.firstRunStep(_card + 1, _cards),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            switch (_card) {
              0 => _Card(
                  icon: Icons.library_add_outlined,
                  title: l10n.firstRunBooksTitle,
                  detail: l10n.firstRunBooksDetail,
                  actions: [
                    _Choice(l10n.importFolder, FirstRunAction.importFolder),
                    _Choice(l10n.firstRunScan, FirstRunAction.scan),
                    _Choice(l10n.firstRunAddOne, FirstRunAction.addOne),
                    _Choice(l10n.firstRunTrySamples, FirstRunAction.trySamples),
                  ],
                ),
              1 => _Card(
                  icon: Icons.cloud_outlined,
                  title: l10n.firstRunServerTitle,
                  detail: l10n.firstRunServerDetail,
                  actions: [
                    _Choice(l10n.firstRunSetUpServer, FirstRunAction.connectServer),
                  ],
                ),
              _ => _Card(
                  icon: Icons.grid_view_outlined,
                  title: l10n.firstRunRoomTitle,
                  detail: l10n.firstRunRoomDetail,
                  actions: [
                    _Choice(l10n.firstRunCreateRoom, FirstRunAction.createRoom),
                  ],
                ),
            },
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.firstRunSkip),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _next,
                  child: Text(_card == _cards - 1 ? l10n.firstRunDone : l10n.firstRunNext),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice {
  const _Choice(this.label, this.action);
  final String label;
  final FirstRunAction action;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String detail;
  final List<_Choice> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(detail),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in actions)
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(choice.action),
                child: Text(choice.label),
              ),
          ],
        ),
      ],
    );
  }
}
