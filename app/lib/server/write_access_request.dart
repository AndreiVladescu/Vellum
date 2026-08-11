import 'package:flutter/material.dart';

import 'connection_store.dart';
import 'server_client.dart';

/// Asking a book's owner for permission to edit it.
///
/// The gap this closes: on a shared library everything is read-only unless the
/// owner has said otherwise, and someone holding a better scan — or a file for
/// a book that has none — had no way to offer it except leaving the app and
/// asking in person.
///
/// It grants nothing. The owner gets a notification and answers it by making a
/// share, which is the same act as any other grant; there is no second,
/// parallel way for permissions to appear.
///
/// **The server is the authority on whether this makes sense.** The app cannot
/// tell, per book, whether this account can already edit it — that is not part
/// of what syncs — so the action is offered wherever there is a server, and a
/// request for a book you can already edit comes back as a plain sentence
/// saying so. Same shape as "Ask to borrow", for the same reason.
Future<void> promptWriteAccessRequest(
  BuildContext context,
  ServerConnection connection,
  String bookId,
  String title,
) async {
  final client = connection.client;
  if (client == null) return;
  final note = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Ask to edit “$title”?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The owner is told, and can give you write access. Nothing '
            'changes until they do.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'e.g. I have a better scan of the cover',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Ask'),
        ),
      ],
    ),
  );
  final text = note.text.trim();
  note.dispose();
  if (send != true || !context.mounted) return;

  try {
    await client.requestWriteAccess(bookId, note: text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asked. The owner has been told.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      // The 400 for "you can already edit this" is a useful sentence, not a
      // failure to hide behind a generic message.
      content: Text(e is ServerException ? e.message : 'That did not work.'),
    ));
  }
}
