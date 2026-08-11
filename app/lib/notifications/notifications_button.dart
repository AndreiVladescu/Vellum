import 'dart:async';

import 'package:flutter/material.dart';

import '../server/connection_store.dart';
import '../server/server_client.dart';
import 'notifications_page.dart';

/// The bell in the library's app bar, with a count of what is waiting.
///
/// This is the "you have something to look at" that the app never had: the
/// server knew a request was pending, and the only way to find out was to go
/// looking. It is checked once when the library opens and again whenever it
/// comes back to the foreground, which is when someone would notice it.
///
/// **It shows nothing at all when there is nothing.** No bell on a library with
/// no server, none on a server too old to have the endpoint, and none while the
/// first check is in flight — a control that is always present and always says
/// zero teaches people to stop looking at it.
class NotificationsButton extends StatefulWidget {
  const NotificationsButton({super.key, required this.connection, this.client});

  final ServerConnection connection;

  /// Injected in tests; see [NotificationsPage.client].
  final VellumServerClient? client;

  @override
  State<NotificationsButton> createState() => _NotificationsButtonState();
}

class _NotificationsButtonState extends State<NotificationsButton>
    with WidgetsBindingObserver {
  int _unread = 0;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the other moment worth a check; polling on a
    // timer would spend a phone's battery to learn nothing most of the time.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final client = widget.client ?? widget.connection.client;
    if (client == null) {
      if (mounted) setState(() => _available = false);
      return;
    }
    try {
      // `unreadOnly` with a small limit: this only needs the count, and the
      // server sends the true total regardless of the page size.
      final result = await client.listNotifications(unreadOnly: true, limit: 1);
      if (!mounted) return;
      setState(() {
        _unread = result.unread;
        _available = true;
      });
    } catch (_) {
      // Offline, or a server without the endpoint. Either way there is nothing
      // useful to show, and an error icon in the app bar would be noise about
      // a feature the person may not use.
      if (mounted) setState(() => _available = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available || _unread == 0) return const SizedBox.shrink();
    return IconButton(
      tooltip: '$_unread unread',
      icon: Badge.count(
        count: _unread,
        child: const Icon(Icons.notifications_none),
      ),
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => NotificationsPage(
            connection: widget.connection,
            client: widget.client,
          ),
        ));
        // Whatever was read in there changes the count out here.
        await _refresh();
      },
    );
  }
}
