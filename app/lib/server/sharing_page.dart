import 'package:flutter/material.dart';
import '../widgets/page_insets.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import 'connection_store.dart';
import 'server_client.dart';

/// Manage the server library's groups, user shares, and public links — a UI
/// over the server's sharing endpoints. Available when connected; the server
/// still enforces who may share what.
class SharingPage extends StatefulWidget {
  const SharingPage({super.key, required this.connection, this.client});

  final ServerConnection connection;

  /// Injectable for tests, as `OpdsBrowserPage` does it; the connection's own
  /// client is used otherwise.
  final VellumServerClient? client;

  @override
  State<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends State<SharingPage> {
  VellumServerClient get _client => widget.client ?? widget.connection.client!;

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
      // Started together, awaited individually — still four concurrent
      // requests, but each result keeps its static type.
      //
      // These used to go through `Future.wait`, which erases a heterogeneous
      // list to `List<dynamic>`: every `results[n] as T` then compiled without
      // the compiler being able to check it. `listBooks` returns a record
      // carrying `server_now` alongside the books, so `as List<ServerBook>`
      // was wrong from the day that field was added and threw on every visit
      // to this screen — a mistake a typed await could not have expressed.
      final groups = _client.listGroups();
      final shares = _client.listShares();
      final links = _client.listLinks();
      final books = _client.listBooks();
      final loaded = (
        groups: await groups,
        shares: await shares,
        links: await links,
        books: (await books).books,
      );
      if (!mounted) return;
      setState(() {
        _groups = loaded.groups;
        _shares = loaded.shares;
        _links = loaded.links;
        _books = loaded.books;
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
            .showSnackBar(SnackBar(content: Text('$e'))); // i18n-ignore: error detail
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).sharingTitle)),
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
    final l10n = L10n.of(context);
    return _Section(
      title: l10n.sharingGroups,
      onAdd: _newGroup,
      addTooltip: l10n.sharingNewGroupTooltip,
      empty: _groups.isEmpty ? l10n.sharingNoGroups : null,
      children: [
        for (final g in _groups)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(g.name),
            subtitle: Text(l10n.sharingGroupBooks(g.bookCount)),
            trailing: IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: l10n.sharingAddBookTooltip,
              onPressed: () => _addBookToGroup(g),
            ),
          ),
      ],
    );
  }

  Future<void> _newGroup() async {
    final l10n = L10n.of(context);
    final name = await _promptText(
        title: l10n.sharingNewGroup, label: l10n.sharingGroupName);
    if (name != null && name.isNotEmpty) {
      await _act(() => _client.createGroup(name));
    }
  }

  Future<void> _addBookToGroup(ServerGroup group) async {
    final bookId = await _pickBook(
        title: L10n.of(context).sharingAddBookTo(group.name));
    if (bookId != null) {
      await _act(() => _client.addBookToGroup(group.id, bookId));
    }
  }

  // ---- shares -------------------------------------------------------------

  Widget _sharesSection(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return _Section(
      title: l10n.sharingShares,
      onAdd: _newShare,
      addTooltip: l10n.sharingNewShareTooltip,
      empty: _shares.isEmpty ? l10n.sharingNoShares : null,
      children: [
        for (final s in _shares)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(s.scopeLabel ?? s.scope),
            subtitle: Text(l10n.sharingGrantee(s.granteeEmail)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(switch (s.permission) {
                    'viewer' => l10n.sharingPermViewer,
                    'editor' => l10n.sharingPermEditor,
                    _ => s.permission,
                  }),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: s.permission == 'editor'
                      ? theme.colorScheme.primaryContainer
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.sharingRevoke,
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
    final l10n = L10n.of(context);
    return _Section(
      title: l10n.sharingLinks,
      onAdd: _books.isEmpty ? null : _newLink,
      addTooltip: l10n.sharingNewLinkTooltip,
      empty: _links.isEmpty ? l10n.sharingNoLinks : null,
      children: [
        for (final l in _links)
          ListTile(
            leading: Icon(l.revoked ? Icons.link_off : Icons.link),
            title: Text(l.bookTitle),
            subtitle: Text(l.revoked
                ? l10n.sharingRevoked
                : l.expiresAt == null
                    ? l10n.sharingNeverExpires
                    : l10n.sharingExpires('${l.expiresAt}')),
            trailing: l.revoked
                ? null
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.sharingRevoke,
                    onPressed: () => _act(() => _client.deleteLink(l.id)),
                  ),
          ),
      ],
    );
  }

  Future<void> _newLink() async {
    final bookId =
        await _pickBook(title: L10n.of(context).sharingLinkFor);
    if (bookId == null) return;
    try {
      final url = await _client.createShareLink(bookId);
      await _load();
      if (mounted) await _showLink(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e'))); // i18n-ignore: error detail
      }
    }
  }

  Future<void> _showLink(String url) {
    final l10n = L10n.of(context);
    return showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.sharingLinkTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.sharingLinkBody),
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
                    SnackBar(content: Text(l10n.sharingLinkCopied)));
              },
              child: Text(l10n.sharingCopy),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.sharingClose),
            ),
          ],
        ),
      );
  }

  // ---- small shared dialogs ----------------------------------------------

  Future<String?> _promptText({required String title, required String label}) {
    final l10n = L10n.of(context);
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
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.create),
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(L10n.of(dialogContext).sharingNoBooks),
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
            FilledButton(
                onPressed: onRetry,
                child: Text(L10n.of(context).sharingRetry)),
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
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.sharingNewShare),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _scope,
              decoration: InputDecoration(labelText: l10n.sharingWhatToShare),
              items: [
                DropdownMenuItem(
                    value: 'all', child: Text(l10n.sharingScopeAll)),
                DropdownMenuItem(
                    value: 'group', child: Text(l10n.sharingScopeGroup)),
                DropdownMenuItem(
                    value: 'book', child: Text(l10n.sharingScopeBook)),
              ],
              onChanged: (v) => setState(() {
                _scope = v!;
                _scopeId = null;
              }),
            ),
            if (_scope == 'group')
              DropdownButtonFormField<String>(
                initialValue: _scopeId,
                decoration: InputDecoration(labelText: l10n.sharingGroupLabel),
                items: [
                  for (final g in widget.groups)
                    DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (v) => setState(() => _scopeId = v),
              ),
            if (_scope == 'book')
              DropdownButtonFormField<String>(
                initialValue: _scopeId,
                decoration: InputDecoration(labelText: l10n.sharingBookLabel),
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
              decoration: InputDecoration(labelText: l10n.sharingRecipient),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _permission,
              decoration: InputDecoration(labelText: l10n.sharingPermission),
              items: [
                DropdownMenuItem(
                    value: 'viewer', child: Text(l10n.sharingViewer)),
                DropdownMenuItem(
                    value: 'editor', child: Text(l10n.sharingEditor)),
              ],
              onChanged: (v) => setState(() => _permission = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: (_targetChosen && _email.text.trim().isNotEmpty)
              ? () => Navigator.of(context).pop(_ShareForm(
                  _scope, _scopeId, _email.text.trim(), _permission))
              : null,
          child: Text(l10n.sharingShare),
        ),
      ],
    );
  }
}
