import 'package:flutter/material.dart';

import '../settings/app_settings.dart';

/// What the user chose to do from the first-run flow, so the caller can navigate.
/// The flow itself opens nothing — it only reports, which keeps it free of every
/// screen it points at.
enum FirstRunAction { importFolder, scan, addOne, connectServer, createRoom }

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
            Text('Welcome to Vellum', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Step ${_card + 1} of $_cards',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            switch (_card) {
              0 => _Card(
                  icon: Icons.library_add_outlined,
                  title: 'Get your books in',
                  detail: 'Point Vellum at a folder of PDFs or EPUBs, scan a '
                      'barcode off a physical book, or add one at a time.',
                  actions: [
                    _Choice('Import a folder', FirstRunAction.importFolder),
                    _Choice('Scan a barcode', FirstRunAction.scan),
                    _Choice('Add one book', FirstRunAction.addOne),
                  ],
                ),
              1 => _Card(
                  icon: Icons.cloud_outlined,
                  title: 'Connect a server?',
                  detail: 'Optional. Vellum works fully offline — a server just '
                      'shares one library across your devices. You can skip '
                      'this forever.',
                  actions: [
                    _Choice('Set up a server', FirstRunAction.connectServer),
                  ],
                ),
              _ => _Card(
                  icon: Icons.grid_view_outlined,
                  title: 'Set up a room?',
                  detail: 'Vellum can draw your real shelves and remember where '
                      'each physical book sits, and who borrowed it.',
                  actions: [
                    _Choice('Create a room', FirstRunAction.createRoom),
                  ],
                ),
            },
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Skip'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _next,
                  child: Text(_card == _cards - 1 ? 'Done' : 'Next'),
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
