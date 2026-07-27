import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../server/connection_store.dart';
import '../server/server_client.dart';

/// Email a book to an e-reader (plan 5 #53).
///
/// The file has to come from the *server* — it is the thing with an outbound
/// mailer — so this is only offered when connected to a server that advertises
/// `send_to_device`. That gate is the whole reason the capability handshake
/// exists: an action that can only fail is worse than a missing one.
///
/// Saved addresses live on the server rather than in app settings, because
/// "my Kindle" is a fact about the person, not about the device they happen to
/// be holding.
class SendToDeviceSheet extends StatefulWidget {
  const SendToDeviceSheet({
    super.key,
    required this.book,
    required this.repository,
    required this.connection,
  });

  final Book book;
  final LibraryRepository repository;
  final ServerConnection connection;

  /// Whether this server can send books by email at all.
  static bool availableOn(ServerConnection? connection) =>
      connection != null &&
      connection.isConnected &&
      (connection.capabilities?.hasFeature('send_to_device') ?? false);

  @override
  State<SendToDeviceSheet> createState() => _SendToDeviceSheetState();
}

class _SendToDeviceSheetState extends State<SendToDeviceSheet> {
  final _address = TextEditingController();
  final _label = TextEditingController();

  List<SendTarget> _targets = const [];
  List<BookFile> _files = const [];
  String? _fileId;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _address.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final files = await widget.repository.watchFilesOf(widget.book.id).first;
    List<SendTarget> targets = const [];
    try {
      targets = await widget.connection.client?.sendTargets() ?? const [];
    } catch (_) {
      // A server that can't list targets can still take a typed address.
    }
    if (!mounted) return;
    setState(() {
      _files = files;
      // EPUB first: every e-reader service accepts it, and Kindle has since
      // 2022 — a PDF is delivered as-is and often unreadable on a small screen.
      _fileId = (files.where((f) => f.format.toLowerCase() == 'epub').firstOrNull
              ?? files.firstOrNull)
          ?.id;
      _targets = targets;
      if (targets.isNotEmpty) _address.text = targets.first.address;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final client = widget.connection.client;
    final fileId = _fileId;
    if (client == null || fileId == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sentTo = await client.sendBookToDevice(
        widget.book.id,
        fileId: fileId,
        to: _address.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${widget.book.title}” sent to $sentTo')),
      );
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _sending = false;
      });
    }
  }

  Future<void> _saveTarget() async {
    final client = widget.connection.client;
    final label = _label.text.trim();
    final address = _address.text.trim();
    if (client == null || label.isEmpty || address.isEmpty) return;
    final updated = [
      for (final t in _targets)
        if (!t.label.toLowerCase().contains(label.toLowerCase())) t,
      SendTarget(label: label, address: address),
    ];
    try {
      final saved = await client.setSendTargets(updated);
      if (!mounted) return;
      setState(() {
        _targets = saved;
        _label.clear();
      });
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send to a device', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Your server emails the file to your e-reader. The '
                    'address it sends *from* usually has to be approved with '
                    'the reader’s service first.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  if (_files.isEmpty)
                    const Text('This book has no digital file to send.')
                  else ...[
                    if (_files.length > 1)
                      DropdownButtonFormField<String>(
                        initialValue: _fileId,
                        decoration: const InputDecoration(
                          labelText: 'Format',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final f in _files)
                            DropdownMenuItem(
                              value: f.id,
                              child: Text(f.format.toUpperCase()),
                            ),
                        ],
                        onChanged: (v) => setState(() => _fileId = v),
                      ),
                    if (_files.length > 1) const SizedBox(height: 12),
                    if (_targets.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final t in _targets)
                            ActionChip(
                              avatar: const Icon(Icons.devices_outlined,
                                  size: 16),
                              label: Text(t.label),
                              onPressed: () =>
                                  setState(() => _address.text = t.address),
                            ),
                        ],
                      ),
                    if (_targets.isNotEmpty) const SizedBox(height: 12),
                    TextField(
                      controller: _address,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Send to',
                        hintText: 'you@kindle.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _label,
                            decoration: const InputDecoration(
                              labelText: 'Save as (optional)',
                              hintText: 'My Kindle',
                              isDense: true,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _sending ? null : _saveTarget,
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            color: theme.colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _sending || _files.isEmpty ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_sending ? 'Sending…' : 'Send'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
