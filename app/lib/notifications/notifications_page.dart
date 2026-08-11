import 'package:flutter/material.dart';

import '../server/connection_store.dart';
import '../server/server_client.dart';
import '../widgets/page_insets.dart';

/// What has happened that this account should know about.
///
/// Lending is a conversation between two people, and the app only ever held its
/// state: a request was pending, then it was approved. Whoever pressed the
/// button knew that. This is the other person's half.
///
/// Fetched, not synced — like [BorrowRequestsPage], a notification is a message
/// to an account on a server and means nothing on a device that isn't
/// connected. A server that predates the endpoint answers 404, and that is
/// reported as "nothing here" rather than an error: the same treatment the
/// personal channel gets, for the same reason.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.connection, this.client});

  final ServerConnection connection;

  /// Injected in tests. In the app this is always `connection.client`, which
  /// mints a fresh client per access and so cannot be held onto.
  final VellumServerClient? client;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<AppNotification>? _items;
  String? _error;
  bool _unsupported = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = widget.client ?? widget.connection.client;
    if (client == null) {
      setState(() => _error = 'Not connected to a server.');
      return;
    }
    try {
      final result = await client.listNotifications();
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _error = null;
      });
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _unsupported = e.statusCode == 404;
        _error = _unsupported ? null : e.message;
        _items = const [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    final client = widget.client ?? widget.connection.client;
    if (client == null) return;
    // Optimistic: the round trip is only bookkeeping, and a failed one is
    // corrected by the next load rather than being worth a dialog.
    setState(() {
      _items = [
        for (final item in _items ?? const <AppNotification>[])
          if (item.id == n.id)
            AppNotification(
              id: item.id,
              kind: item.kind,
              title: item.title,
              body: item.body,
              bookId: item.bookId,
              createdAt: item.createdAt,
              readAt: DateTime.now(),
            )
          else
            item,
      ];
    });
    try {
      await client.markNotificationRead(n.id);
    } catch (_) {
      await _load();
    }
  }

  Future<void> _markAllRead() async {
    final client = widget.client ?? widget.connection.client;
    if (client == null) return;
    try {
      await client.markAllNotificationsRead();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final unread = items?.where((n) => !n.isRead).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _body(items),
      ),
    );
  }

  Widget _body(List<AppNotification>? items) {
    if (_error != null) {
      return _centered(_error!);
    }
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_unsupported) {
      return _centered(
        'This server is older than notifications. Everything else works; '
        'update the server to be told when someone asks to borrow a book.',
      );
    }
    if (items.isEmpty) {
      return _centered('Nothing has happened yet.');
    }
    return ListView.separated(
      padding: pageInsets(context, EdgeInsets.zero),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = items[i];
        return ListTile(
          leading: Icon(
            _iconFor(n.kind),
            color: n.isRead
                ? Theme.of(context).colorScheme.outline
                : Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            n.title,
            style: TextStyle(
              fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600,
            ),
          ),
          subtitle: Text(
            [
              if (n.body != null) n.body!,
              if (n.createdAt != null) _ago(n.createdAt!),
            ].join('\n'),
          ),
          isThreeLine: n.body != null,
          onTap: () => _markRead(n),
        );
      },
    );
  }

  Widget _centered(String message) => ListView(
        // A ListView so pull-to-refresh still works on an empty screen —
        // "nothing yet" is exactly when someone tries to refresh.
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
        children: [Text(message, textAlign: TextAlign.center)],
      );

  /// Unknown kinds fall through to a neutral icon rather than an error: the
  /// server sends a title that already reads as a sentence.
  static IconData _iconFor(String kind) => switch (kind) {
        'borrow.requested' => Icons.pan_tool_outlined,
        'borrow.approved' => Icons.check_circle_outline,
        'borrow.declined' => Icons.cancel_outlined,
        'borrow.cancelled' => Icons.undo,
        _ => Icons.notifications_none,
      };

  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-'
        '${when.day.toString().padLeft(2, '0')}';
  }
}
