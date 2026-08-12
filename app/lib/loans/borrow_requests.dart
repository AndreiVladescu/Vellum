import 'package:flutter/material.dart';
import '../widgets/page_insets.dart';

import '../server/connection_store.dart';
import '../server/server_client.dart';

/// Borrow requests in the app (plan 5 #49).
///
/// The owner's half of the loop: what people have asked to borrow, and the two
/// buttons that answer them. Approving creates the loan **server-side**, in one
/// transaction with closing the request — so this screen never has to keep the
/// two in step itself, which is exactly the sort of bookkeeping a client gets
/// wrong when the network drops halfway.
///
/// Fetched, not synced: a request is a conversation between two accounts on a
/// server, and has no meaning on a device that isn't connected.
class BorrowRequestsPage extends StatefulWidget {
  const BorrowRequestsPage({super.key, required this.connection});

  final ServerConnection connection;

  @override
  State<BorrowRequestsPage> createState() => _BorrowRequestsPageState();
}

class _BorrowRequestsPageState extends State<BorrowRequestsPage> {
  List<BorrowRequest>? _incoming;
  List<BorrowRequest>? _outgoing;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = widget.connection.client;
    if (client == null) {
      setState(() => _error = 'Not connected to a server.');
      return;
    }
    setState(() => _busy = true);
    try {
      final incoming = await client.listBorrowRequests();
      final outgoing =
          await client.listBorrowRequests(direction: 'outgoing');
      if (!mounted) return;
      setState(() {
        _incoming = incoming;
        _outgoing = outgoing;
        _error = null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ServerException ? e.message : "Couldn't reach the server.";
        _busy = false;
      });
    }
  }

  Future<void> _decide(BorrowRequest request, String decision) async {
    final client = widget.connection.client;
    if (client == null) return;

    DateTime? dueAt;
    String? reply;
    if (decision == 'approved') {
      // The same presets as lending by hand (plan 5 #27): most lending is "a
      // couple of weeks", and "no date" has to be as easy as the rest.
      dueAt = await _askDueDate();
      if (!mounted) return;
    } else if (decision == 'declined') {
      reply = await _askReply();
      if (reply == null || !mounted) return; // cancelled the dialog
    }

    try {
      await client.decideBorrowRequest(
        request.id,
        status: decision,
        reply: reply,
        dueAt: dueAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision == 'approved'
            ? 'Approved — “${request.bookTitle}” is now on loan to '
                '${request.requesterEmail}.'
            : 'Answered ${request.requesterEmail}.'),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is ServerException ? e.message : 'That did not work.'),
      ));
    }
  }

  /// Returns the chosen date, or null for "no agreed date" — which is a real
  /// arrangement, not a blank field.
  Future<DateTime?> _askDueDate() async {
    final now = DateTime.now();
    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Due back?'),
        children: [
          for (final (label, days) in [('In 2 weeks', 14), ('In a month', 30)])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(now.add(Duration(days: days))),
              child: Text(label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('No date'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askReply() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Say why (optional)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. it’s already lent out',
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
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incoming = _incoming ?? const <BorrowRequest>[];
    final outgoing = _outgoing ?? const <BorrowRequest>[];
    final pending = incoming.where((r) => r.isPending).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Borrow requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _incoming == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: pageInsets(context, EdgeInsets.zero),
                  children: [
                    _Header('To answer (${pending.length})'),
                    if (pending.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Text('Nobody is waiting on you.'),
                      )
                    else
                      for (final request in pending)
                        ListTile(
                          leading: const Icon(Icons.pan_tool_alt_outlined),
                          title: Text(request.bookTitle),
                          subtitle: Text(
                            '${request.requesterEmail}'
                            '${request.note == null ? '' : '\n“${request.note}”'}',
                          ),
                          isThreeLine: request.note != null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _decide(request, 'declined'),
                                child: const Text('Decline'),
                              ),
                              FilledButton(
                                onPressed: () => _decide(request, 'approved'),
                                child: const Text('Lend it'),
                              ),
                            ],
                          ),
                        ),
                    if (outgoing.isNotEmpty)
                      ExpansionTile(
                        title: Text('You asked for (${outgoing.length})'),
                        children: [
                          for (final request in outgoing)
                            ListTile(
                              dense: true,
                              leading: Icon(switch (request.status) {
                                'approved' => Icons.check_circle_outline,
                                'declined' => Icons.cancel_outlined,
                                'cancelled' => Icons.undo,
                                _ => Icons.schedule,
                              }),
                              title: Text(request.bookTitle),
                              subtitle: Text(
                                [
                                  if (request.ownerName != null)
                                    'asked ${request.ownerName}',
                                  request.status,
                                  if (request.reply != null)
                                    '“${request.reply}”',
                                ].join(' · '),
                              ),
                              trailing: request.isPending
                                  ? TextButton(
                                      onPressed: () =>
                                          _decide(request, 'cancelled'),
                                      child: const Text('Withdraw'),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    // Decided incoming requests, so "who did I say no to?" has
                    // an answer without a trip to the console.
                    if (incoming.any((r) => !r.isPending))
                      ExpansionTile(
                        title: Text(
                          'Answered (${incoming.where((r) => !r.isPending).length})',
                        ),
                        children: [
                          for (final request
                              in incoming.where((r) => !r.isPending))
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.history),
                              title: Text(request.bookTitle),
                              subtitle: Text(
                                '${request.requesterEmail} · ${request.status}',
                              ),
                            ),
                        ],
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Approving creates the loan for you — it appears on the '
                        'Loans page with the due date you chose.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// "Request to borrow" for a book someone else owns.
///
/// Offered only when the server advertises `borrow_requests` **and** the book
/// isn't yours — asking to borrow your own book is a button that can only
/// produce an error message.
/// Asks the owner to lend [title].
///
/// [owner] is who will be asked, when the app knows — `books.added_by`, cached
/// from the server. Naming them was the report: "it is not clear who I ask for
/// a book". Null falls back to "the owner", which is what a library with an
/// older server can honestly say.
Future<void> promptBorrowRequest(
  BuildContext context,
  ServerConnection connection,
  String bookId,
  String title, {
  String? owner,
}) async {
  final client = connection.client;
  if (client == null) return;
  final note = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Ask to borrow “$title”?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${owner ?? 'The owner'} sees this in their app and can lend it '
            'to you. Nothing happens until they say yes, and you are told '
            'either way.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'e.g. for the weekend',
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
    await client.requestToBorrow(bookId: bookId, note: text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asked. You’ll see the answer here.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(e is ServerException ? e.message : 'That did not work.'),
    ));
  }
}
