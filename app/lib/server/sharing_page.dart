import 'package:flutter/material.dart';
import '../widgets/page_insets.dart';
import 'package:flutter/services.dart';

import 'connection_store.dart';
import 'server_client.dart';

/// Manage the server library's groups, user shares, and public links — a UI
/// over the server's sharing endpoints. Available when connected; the server
/// still enforces who may share what.
class SharingPage extends StatefulWidget {
  const SharingPage({super.key, required this.connection});

  final ServerConnection connection;

  @override
  State<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends State<SharingPage> {
  VellumServerClient get _client => widget.connection.client!;

  List<ServerGroup> _groups = const [];
  List<ServerShare> _shares = const [];
  List<ServerLink> _links = const [];
  List<ServerBook> _books = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _client.listGroups(),
        _client.listShares(),
        _client.listLinks(),
        _client.listBooks(),
      ]);
      if (!mounted) return;
      setState(() {
        _groups = results[0] as List<ServerGroup>;
        _shares = results[1] as List<ServerShare>;
        _links = results[2] as List<ServerLink>;
        _books = results[3] as List<ServerBook>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Runs [action], then refreshes; surfaces any error as a snackbar.
  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sharing')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorRetry(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: pageInsets(context, EdgeInsets.all(16)),
                    children: [
                      _groupsSection(context),
                      const Divider(height: 32),
                      _sharesSection(context),
                      const Divider(height: 32),
                      _linksSection(context),
                    ],
                  ),
                ),
    );
  }

  // ---- groups -------------------------------------------------------------

  Widget _groupsSection(BuildContext context) {
    return _Section(
      title: 'Groups',
      onAdd: _newGroup,
      addTooltip: 'New group',
      empty: _groups.isEmpty ? 'No groups yet.' : null,
      children: [
        for (final g in _groups)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(g.name),
            subtitle: Text('${g.bookCount} book${g.bookCount == 1 ? '' : 's'}'),
            trailing: IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Add a book',
              onPressed: () => _addBookToGroup(g),
            ),
          ),
      ],
    );
  }

  Future<void> _newGroup() async {
    final name = await _promptText(title: 'New group', label: 'Group name');
    if (name != null && name.isNotEmpty) {
      await _act(() => _client.createGroup(name));
    }
  }

  Future<void> _addBookToGroup(ServerGroup group) async {
    final bookId = await _pickBook(title: 'Add a book to ${group.name}');
    if (bookId != null) {
      await _act(() => _client.addBookToGroup(group.id, bookId));
    }
  }

  // ---- shares -------------------------------------------------------------

  Widget _sharesSection(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      title: 'Shared with people',
      onAdd: _newShare,
      addTooltip: 'New share',
      empty: _shares.isEmpty ? 'Nothing shared yet.' : null,
      children: [
        for (final s in _shares)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(s.scopeLabel ?? s.scope),
            subtitle: Text('→ ${s.granteeEmail}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(s.permission),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: s.permission == 'editor'
                      ? theme.colorScheme.primaryContainer
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Revoke',
                  onPressed: () => _act(() => _client.deleteShare(s.id)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _newShare() async {
    final result = await showDialog<_ShareForm>(
      context: context,
      builder: (_) => _ShareDialog(groups: _groups, books: _books),
    );
    if (result != null) {
      await _act(() => _client.createShare(
            scope: result.scope,
            scopeId: result.scopeId,
            granteeEmail: result.email,
            permission: result.permission,
          ));
    }
  }

  // ---- public links -------------------------------------------------------

  Widget _linksSection(BuildContext context) {
    return _Section(
      title: 'Public links',
      onAdd: _books.isEmpty ? null : _newLink,
      addTooltip: 'New link',
      empty: _links.isEmpty ? 'No public links.' : null,
      children: [
        for (final l in _links)
          ListTile(
            leading: Icon(l.revoked ? Icons.link_off : Icons.link),
            title: Text(l.bookTitle),
            subtitle: Text(l.revoked
                ? 'Revoked'
                : l.expiresAt == null
                    ? 'Never expires'
                    : 'Expires ${l.expiresAt}'),
            trailing: l.revoked
                ? null
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Revoke',
                    onPressed: () => _act(() => _client.deleteLink(l.id)),
                  ),
          ),
      ],
    );
  }

  Future<void> _newLink() async {
    final bookId = await _pickBook(title: 'Public link for which book?');
    if (bookId == null) return;
    try {
      final url = await _client.createShareLink(bookId);
      await _load();
      if (mounted) await _showLink(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showLink(String url) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Public link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Anyone with this link can read the book. It is shown '
                  'once — copy it now.'),
              const SizedBox(height: 12),
              SelectableText(url, style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied.')));
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  // ---- small shared dialogs ----------------------------------------------

  Future<String?> _promptText({required String title, required String label}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickBook({required String title}) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final b in _books)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(b.id),
              child: Text(b.title),
            ),
          if (_books.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No books on the server yet.'),
            ),
        ],
      ),
    );
  }
}

/// A titled section with an optional add button and an empty-state message.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.onAdd,
    this.addTooltip,
    this.empty,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onAdd;
  final String? addTooltip;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            if (onAdd != null)
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: addTooltip,
                onPressed: onAdd,
              ),
          ],
        ),
        if (empty != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(empty!, style: theme.textTheme.bodySmall),
          )
        else
          ...children,
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Result of the new-share dialog.
class _ShareForm {
  _ShareForm(this.scope, this.scopeId, this.email, this.permission);
  final String scope;
  final String? scopeId;
  final String email;
  final String permission;
}

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.groups, required this.books});

  final List<ServerGroup> groups;
  final List<ServerBook> books;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  String _scope = 'all';
  String? _scopeId;
  String _permission = 'viewer';
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _targetChosen => _scope == 'all' || _scopeId != null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New share'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _scope,
              decoration: const InputDecoration(labelText: 'What to share'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Entire library')),
                DropdownMenuItem(value: 'group', child: Text('A group')),
                DropdownMenuItem(value: 'book', child: Text('A single book')),
              ],
              onChanged: (v) => setState(() {
                _scope = v!;
                _scopeId = null;
              }),
            ),
            if (_scope == 'group')
              DropdownButtonFormField<String>(
                initialValue: _scopeId,
                decoration: const InputDecoration(labelText: 'Group'),
                items: [
                  for (final g in widget.groups)
                    DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (v) => setState(() => _scopeId = v),
              ),
            if (_scope == 'book')
              DropdownButtonFormField<String>(
                initialValue: _scopeId,
                decoration: const InputDecoration(labelText: 'Book'),
                items: [
                  for (final b in widget.books)
                    DropdownMenuItem(value: b.id, child: Text(b.title)),
                ],
                onChanged: (v) => setState(() => _scopeId = v),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: "Recipient's email"),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _permission,
              decoration: const InputDecoration(labelText: 'Permission'),
              items: const [
                DropdownMenuItem(value: 'viewer', child: Text('Viewer (read)')),
                DropdownMenuItem(
                    value: 'editor', child: Text('Editor (read + edit)')),
              ],
              onChanged: (v) => setState(() => _permission = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_targetChosen && _email.text.trim().isNotEmpty)
              ? () => Navigator.of(context).pop(_ShareForm(
                  _scope, _scopeId, _email.text.trim(), _permission))
              : null,
          child: const Text('Share'),
        ),
      ],
    );
  }
}
