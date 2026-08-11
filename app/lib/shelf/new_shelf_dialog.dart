import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// What [showNewShelfDialog] returns: the name, and who the shelf is for.
typedef NewShelf = ({String name, bool personal});

/// Asks for a shelf's name and, on a shared library, who it is for.
///
/// A shelf is an opinion about how books go together, and on a server with
/// several people that opinion used to arrive on everyone's screen whether or
/// not it was meant for them. Asking once, at the moment the shelf is made, is
/// cheaper than a settings screen nobody visits — and it is the moment when the
/// answer is actually known.
///
/// **The question only appears when there is a server.** On a library with no
/// server every shelf is already personal in the only sense that matters, so
/// offering the choice would be asking about a distinction that does not exist
/// yet. Those shelves are created shared, which is what they become if the
/// library is later connected — the same thing that happened to every shelf
/// made before this existed.
Future<NewShelf?> showNewShelfDialog(
  BuildContext context, {
  required bool hasServer,
}) {
  return showDialog<NewShelf>(
    context: context,
    builder: (context) => _NewShelfDialog(hasServer: hasServer),
  );
}

class _NewShelfDialog extends StatefulWidget {
  const _NewShelfDialog({required this.hasServer});

  final bool hasServer;

  @override
  State<_NewShelfDialog> createState() => _NewShelfDialogState();
}

class _NewShelfDialogState extends State<_NewShelfDialog> {
  final _controller = TextEditingController();
  bool _personal = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, personal: _personal));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.shelfNew),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.shelfNameHint),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.hasServer) ...[
            const SizedBox(height: 16),
            // Radios rather than a switch: these are two named kinds of shelf,
            // and a switch would make one of them the absence of the other.
            RadioGroup<bool>(
              groupValue: _personal,
              onChanged: (v) => setState(() => _personal = v ?? false),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool>(
                    value: false,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Shared'),
                    subtitle: Text(
                      'Everyone the library is shared with sees this shelf.',
                    ),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Personal'),
                    subtitle: Text(
                      'Only you. It still syncs to your own devices.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
