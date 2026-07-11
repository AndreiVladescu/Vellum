import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import 'cert_trust.dart';
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
    required this.sync,
  });

  final ServerConnection connection;
  final LibraryRepository repository;

  /// The app-wide sync service (shared with the launch auto-sync, so its
  /// re-entrancy guard spans both).
  final SyncService sync;

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

  SyncService get _sync => widget.sync;

  bool _busy = false;
  bool _registerMode = false;
  String? _error;

  // Live sync progress: [0..1] fraction and the current phase label.
  double? _progress;
  String _phase = '';

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
      if (e.isUnauthorized) {
        // The session expired or was revoked — drop to the sign-in screen.
        await widget.connection.clearExpiredSession();
        if (mounted) {
          setState(() => _error = 'Session expired — please log in again.');
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } on StateError {
      // A sync (usually the launch auto-sync) is already in flight — the server
      // is fine, so don't render the internal "Bad state" message.
      if (mounted) {
        setState(() => _error = 'A sync is already running — try again in a moment.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reach the server.\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _phase = '';
        });
      }
    }
  }

  void _onProgress(int done, int total, String phase) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _progress = total == 0 ? null : done / total;
    });
  }

  /// Post-sync feedback: a count, plus a Details action when anything failed.
  void _showReport(String verb, int count, SyncReport report) {
    if (!mounted) return;
    final n = report.issues.length;
    final msg = report.hasIssues
        ? '$verb $count book${count == 1 ? '' : 's'}, '
              '$n issue${n == 1 ? '' : 's'}'
        : (count == 0
              ? 'Already up to date.'
              : '$verb $count book${count == 1 ? '' : 's'}.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: report.hasIssues
            ? SnackBarAction(
                label: 'Details',
                onPressed: () => _showIssues(report.issues),
              )
            : null,
      ),
    );
  }

  void _showIssues(List<SyncIssue> issues) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sync issues (${issues.length})'),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final i in issues)
                ListTile(
                  dense: true,
                  title: Text(i.title.isEmpty ? i.bookId : i.title),
                  subtitle: Text('${i.stage}: ${i.message}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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

  Future<void> _syncNow() => _run(() async {
        final client = widget.connection.client;
        if (client == null) return;
        final report = await _sync.sync(
          client,
          cursor: widget.connection.syncCursor,
          onCursor: widget.connection.setSyncCursor,
          onProgress: _onProgress,
        );
        if (!mounted) return;
        final n = report.issues.length;
        final changed = report.pulled + report.pushed;
        final msg = changed == 0 && !report.hasIssues
            ? 'Already up to date.'
            : 'Pulled ${report.pulled}, pushed ${report.pushed}'
                '${report.hasIssues ? ', $n issue${n == 1 ? '' : 's'}' : ''}.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            action: report.hasIssues
                ? SnackBarAction(
                    label: 'Details',
                    onPressed: () => _showIssues(report.issues),
                  )
                : null,
          ),
        );
      });

  Future<void> _pull() => _run(() async {
        final client = widget.connection.client;
        if (client == null) return;
        final report = await _sync.pull(
          client,
          cursor: widget.connection.syncCursor,
          onCursor: widget.connection.setSyncCursor,
          onProgress: _onProgress,
        );
        _showReport('Pulled', report.pulled, report);
      });

  Future<void> _push() => _run(() async {
        final client = widget.connection.client;
        if (client == null) return;
        final report = await _sync.push(client, onProgress: _onProgress);
        _showReport('Pushed', report.pushed, report);
      });

  /// Certificate status + import control, shown for https URLs (a self-signed
  /// server needs its certificate imported before the handshake can succeed).
  Widget _certRow(ThemeData theme) {
    final isHttps = ServerConnection.normalizeUrl(_url.text).startsWith('https://');
    if (!isHttps) return const SizedBox.shrink();
    final pem = widget.connection.certFor(_url.text);
    final fp = pem == null ? null : fingerprintOf(pem);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            pem == null ? Icons.shield_outlined : Icons.verified_user,
            size: 18,
            color: pem == null
                ? theme.colorScheme.outline
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pem == null
                  ? 'No certificate trusted — import it for a self-signed server.'
                  : 'Trusted certificate ${_shortFingerprint(fp!)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _importCert,
            child: Text(pem == null ? 'Import' : 'Change'),
          ),
        ],
      ),
    );
  }

  /// First few groups of a fingerprint, enough to eyeball against the server's.
  String _shortFingerprint(String fp) {
    final groups = fp.split(':');
    return groups.length <= 6 ? fp : '${groups.take(6).join(':')}…';
  }

  /// Import the server's certificate for the current URL — pasted as PEM or read
  /// from a chosen `.pem`/`.crt` file. Passing an empty result forgets it.
  Future<void> _importCert() async {
    final url = _url.text;
    final controller =
        TextEditingController(text: widget.connection.certFor(url) ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        String? err;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Trust server certificate'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Paste the server's certificate, or choose its cert.pem file. "
                    'Check the fingerprint matches the one the server printed on '
                    'startup before trusting it.',
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        const group = XTypeGroup(
                          label: 'Certificate',
                          extensions: ['pem', 'crt', 'cer'],
                        );
                        final file =
                            await openFile(acceptedTypeGroups: const [group]);
                        if (file != null) {
                          controller.text = await File(file.path).readAsString();
                          setLocal(() => err = null);
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose file…'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    maxLines: 6,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '-----BEGIN CERTIFICATE-----',
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err!,
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              if (widget.connection.certFor(url) != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Remove'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final pem = controller.text.trim();
                  if (pem.isEmpty) {
                    Navigator.pop(context, '');
                    return;
                  }
                  if (fingerprintOf(pem) == null) {
                    setLocal(() =>
                        err = "That doesn't look like a PEM certificate.");
                    return;
                  }
                  Navigator.pop(context, pem);
                },
                child: const Text('Trust'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return; // cancelled
    await widget.connection.setCert(url, result.isEmpty ? null : result);
    if (mounted) setState(() {});
  }

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
            'Sync pulls the books shared with you into your local shelf, then '
            'pushes your local changes up to the server. It also runs '
            'automatically when the app starts.'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : _syncNow,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          title: Text('Advanced', style: theme.textTheme.titleSmall),
          subtitle: const Text('Run only one direction of the sync'),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pull,
                  icon: const Icon(Icons.download),
                  label: const Text('Pull library'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _push,
                  icon: const Icon(Icons.upload),
                  label: const Text('Push my books'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
          if (_phase.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_phase, style: theme.textTheme.bodySmall),
          ],
        ],
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
        _certRow(theme),
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
