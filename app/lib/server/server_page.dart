import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import 'connection_store.dart';
import 'server_client.dart';
import 'sharing_page.dart';
import 'sync_service.dart';

/// Connect the app to a Vellum sync server: log in (or register the first,
/// master account), then pull the shared library onto this device.
class ServerPage extends StatefulWidget {
  const ServerPage({
    super.key,
    required this.connection,
    required this.repository,
  });

  final ServerConnection connection;
  final LibraryRepository repository;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  late final TextEditingController _url = TextEditingController(
    text: widget.connection.baseUrl.isEmpty
        ? 'http://localhost:3000'
        : widget.connection.baseUrl,
  );
  final _email = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _registerMode = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ServerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reach the server.\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authenticate() => _run(() async {
        final url = _url.text;
        final client = widget.connection.anonymousClient(url);
        final auth = _registerMode
            ? await client.register(
                email: _email.text.trim(),
                displayName: _displayName.text.trim().isEmpty
                    ? _email.text.trim()
                    : _displayName.text.trim(),
                password: _password.text,
              )
            : await client.login(
                email: _email.text.trim(),
                password: _password.text,
              );
        await widget.connection.saveSession(url: url, auth: auth);
      });

  Future<void> _pull() => _run(() async {
        final client = widget.connection.client;
        if (client == null) return;
        final count = await SyncService(widget.repository).pull(client);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(count == 0
                ? 'No books on the server yet.'
                : 'Pulled $count book${count == 1 ? '' : 's'} onto this device.'),
          ));
        }
      });

  Future<void> _push() => _run(() async {
        final client = widget.connection.client;
        if (client == null) return;
        final count = await SyncService(widget.repository).push(client);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Pushed $count book${count == 1 ? '' : 's'} '
                'to the server.'),
          ));
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library server')),
      body: ListenableBuilder(
        listenable: widget.connection,
        builder: (context, _) => widget.connection.isConnected
            ? _buildConnected(context)
            : _buildSignIn(context),
      ),
    );
  }

  Widget _buildConnected(BuildContext context) {
    final theme = Theme.of(context);
    final conn = widget.connection;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: Text(conn.email),
            subtitle: Text(conn.baseUrl),
            trailing: conn.isMaster
                ? Chip(
                    label: const Text('Master'),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 24),
        Text('Sync', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Pull the books shared with you into your local shelf, or push your '
            'local books up to the server. Neither side deletes.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pull,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: const Text('Pull library'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _push,
              icon: const Icon(Icons.upload),
              label: const Text('Push my books'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Text('Sharing', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Create book groups, share the library or a book with other '
            'accounts, and mint public links.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        SharingPage(connection: widget.connection),
                  )),
          icon: const Icon(Icons.group_outlined),
          label: const Text('Manage sharing'),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => widget.connection.disconnect(),
          icon: const Icon(Icons.logout),
          label: const Text('Disconnect'),
        ),
      ],
    );
  }

  Widget _buildSignIn(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          _registerMode ? 'Create the master account' : 'Sign in to a server',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _registerMode
              ? 'The first account on a fresh server becomes its master (owner).'
              : 'Connect to a self-hosted Vellum server to access a shared '
                  'library.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'https://library.example.com',
            border: OutlineInputBorder(),
          ),
        ),
        if (ServerConnection.normalizeUrl(_url.text).startsWith('http://')) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.lock_open, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Unencrypted connection — your password and books are sent '
                  'in cleartext.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        if (_registerMode) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _displayName,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          onSubmitted: (_) => _busy ? null : _authenticate(),
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _authenticate,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_registerMode ? 'Create account' : 'Log in'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _registerMode = !_registerMode;
                    _error = null;
                  }),
          child: Text(_registerMode
              ? 'Have an account? Log in'
              : 'Setting up a new server? Create the master account'),
        ),
      ],
    );
  }
}
