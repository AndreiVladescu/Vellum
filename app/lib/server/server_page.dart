import 'dart:async';
import 'dart:io';

import '../widgets/page_insets.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../account/user_profile.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/labels.dart';
import '../notifications/sync_tray.dart';
import '../settings/app_settings.dart';
import '../snack_bars.dart';
import 'cert_trust.dart';
import 'connection_store.dart';
import 'server_client.dart';
import 'sharing_page.dart';
import 'sync_foreground_service.dart';
import 'sync_scope_page.dart';
import 'sync_service.dart';

/// Connect the app to a Vellum sync server: log in (or register the first,
/// master account), then pull the shared library onto this device.
class ServerPage extends StatefulWidget {
  const ServerPage({
    super.key,
    required this.connection,
    required this.repository,
    required this.sync,
    required this.settings,
    this.profile,
  });

  final ServerConnection connection;
  final LibraryRepository repository;

  /// Read for the "Sync reading position" opt-in and this device's identity
  /// (plan 5 #5) — the manual Sync action honours the same preference the
  /// launch sync does.
  final AppSettingsStore settings;

  /// The local profile, so signing in can reconcile it with the account
  /// (plan 6 #5). Optional: the page works without one, it just can't ask.
  final UserProfileStore? profile;

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
  SyncPhase? _phase;

  // The Android status-bar counterpart to the two fields above: a
  // notification with the same progress, live only while _notifyingSync is
  // true (the main Sync action, below) — Pull/Push under Advanced don't set
  // it, so _onProgress's calls from those don't post a notification too.
  final _syncTray = SyncNotificationTray();
  bool _notifyingSync = false;

  @override
  void initState() {
    super.initState();
    // Covers the app-restart case: _authenticate() (below) only runs on a
    // fresh sign-in, but a resumed session is "connected" without it ever
    // running this session. Best-effort and silent — see fetchCapabilities.
    if (widget.connection.isConnected) {
      widget.connection.fetchCapabilities();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  /// [isAuthAttempt] is true only for [_authenticate]'s own call: a 401 from
  /// *logging in* means the credentials were wrong (or the account is
  /// throttled), which is a completely different fact from a 401 on an
  /// already-authenticated call, which means *this device's* session died.
  /// Both used to show "Session expired — please log in again", which is a
  /// straightforwardly wrong thing to tell someone who just mistyped a
  /// password or got rate-limited — and there is no session to clear in the
  /// first case, since one was never established.
  Future<void> _run(
    Future<void> Function() action, {
    bool isAuthAttempt = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ServerException catch (e) {
      if (e.isUnauthorized && !isAuthAttempt) {
        // The session expired or was revoked — drop to the sign-in screen.
        await widget.connection.clearExpiredSession();
        if (mounted) {
          setState(() => _error = L10n.of(context).serverSessionExpired);
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } on StateError {
      // A sync (usually the launch auto-sync) is already in flight — the server
      // is fine, so don't render the internal "Bad state" message.
      if (mounted) {
        setState(() => _error = L10n.of(context).serverSyncRunning);
      }
    } on TlsException {
      // Covers HandshakeException / CertificateException: the imported/pinned
      // server certificate didn't match (rotated, regenerated, or never
      // imported). Point the user at the fix rather than a raw exception.
      if (mounted) {
        setState(() => _error = L10n.of(context).serverCertUntrusted);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = L10n.of(context).serverUnreachable('$e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _phase = null;
        });
      }
    }
  }

  /// The last phase announced, so a screen reader hears "Pushing books" once
  /// rather than once per book. A progress bar is invisible to a screen reader
  /// and a sync is the app's longest silent operation, so *something* has to
  /// be said (plan 5 #42) — but a 400-book push announcing every increment
  /// would be unusable. Phase changes are the meaningful events.
  SyncPhase? _announcedPhase;

  /// Speaks [message] to a screen reader, if this platform can.
  ///
  /// `sendAnnouncement` needs the view it belongs to, and
  /// `MediaQuery.supportsAnnounceOf` is the platform's own answer to whether
  /// announcements do anything here — checking it keeps this a no-op rather
  /// than a silent failure on platforms that ignore the channel.
  void _announce(String message) {
    if (!mounted) return;
    if (!MediaQuery.supportsAnnounceOf(context)) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  void _onProgress(int done, int total, SyncPhase phase) {
    // Kept outside the `if (!mounted)` guard below: the whole point of the
    // notification is to still be useful once the app (and this State) is
    // backgrounded, which is exactly when `mounted` stops being a reliable
    // signal to gate anything sync-related on.
    if (_notifyingSync) unawaited(_syncTray.update(done, total, phase));
    if (!mounted) return;
    if (phase != _announcedPhase) {
      _announcedPhase = phase;
      _announce(phase.labelOf(L10n.of(context)));
    }
    setState(() {
      _phase = phase;
      _progress = total == 0 ? null : done / total;
    });
  }

  /// Post-sync feedback: a count, plus a Details action when anything failed.
  void _showReport(bool pulled, int count, SyncReport report) {
    if (!mounted) return;
    final l10n = L10n.of(context);
    final issues = l10n.syncIssues(report.issues.length);
    final msg = report.hasIssues
        ? (pulled
              ? l10n.serverPulledBooksIssues(count, issues)
              : l10n.serverPushedBooksIssues(count, issues))
        : (count == 0
              ? l10n.serverUpToDate
              : (pulled
                    ? l10n.serverPulledBooks(count)
                    : l10n.serverPushedBooks(count)));
    // A snackbar is announced by the platform on Android but not reliably on
    // desktop, and this is the one message that says whether the sync worked.
    _announce(msg);
    _announcedPhase = null;
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar(
        content: Text(msg),
        action: report.hasIssues
            ? SnackBarAction(
                label: l10n.serverDetails,
                onPressed: () => _showIssues(report.issues),
              )
            : null,
      ),
    );
  }

  /// A dialog-content width that caps at [max] on desktop but shrinks to fit a
  /// phone screen (an AlertDialog reserves ~80px of horizontal inset padding).
  double _dialogWidth(BuildContext context, double max) =>
      (MediaQuery.sizeOf(context).width - 80).clamp(0.0, max);

  /// A book's title, or its id when the title is blank, or the personal-data
  /// group for issues that belong to no single book.
  String _issueTitle(SyncIssue i, L10n l10n) {
    if (i.title.isNotEmpty) return i.title;
    return i.bookId.isEmpty ? l10n.syncIssuePersonalData : i.bookId;
  }

  void _showIssues(List<SyncIssue> issues) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).serverIssuesTitle(issues.length)),
        content: SizedBox(
          width: _dialogWidth(context, 400),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final i in issues)
                ListTile(
                  dense: true,
                  title: Text(_issueTitle(i, L10n.of(context))),
                  subtitle: Text(
                    '${i.stage}: ${i.messageOf(L10n.of(context))}',
                  ), // i18n-ignore: technical detail
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.of(context).serverClose),
          ),
        ],
      ),
    );
  }

  /// Whether the server at the typed address can send mail.
  ///
  /// Probed from the *unauthenticated* capability endpoint as the address is
  /// typed — there is no session yet, which is the whole point of a reset.
  bool _mailAvailable = false;
  String _probedUrl = '';

  Future<void> _probeMail(String rawUrl) async {
    final url = ServerConnection.normalizeUrl(rawUrl);
    if (url.isEmpty || url == _probedUrl) return;
    _probedUrl = url;
    try {
      final caps = await widget.connection.anonymousClient(url).capabilities();
      if (!mounted || ServerConnection.normalizeUrl(_url.text) != url) return;
      setState(() => _mailAvailable = caps.hasFeature('mail'));
    } catch (_) {
      // Unreachable, or a server too old to answer: assume no mail rather than
      // offering a link that would fail.
      if (mounted) setState(() => _mailAvailable = false);
    }
  }

  /// Asks the server to email a reset link.
  ///
  /// The confirmation is deliberately non-committal: the server answers
  /// identically whether or not the address has an account, and echoing "we
  /// sent you an email" would turn this screen into an account-existence
  /// oracle the server took care not to be.
  Future<void> _forgotPassword() async {
    final l10n = L10n.of(context);
    final email = TextEditingController(text: _email.text.trim());
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.serverResetTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.serverResetBody),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l10n.serverEmail),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.serverSendLink),
          ),
        ],
      ),
    );
    final address = email.text.trim();
    email.dispose();
    if (send != true || address.isEmpty || !mounted) return;

    try {
      await widget.connection
          .anonymousClient(_url.text)
          .forgotPassword(address);
    } catch (_) {
      // Fall through to the same message: a failure here would otherwise leak
      // whether the address is known.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.serverResetSent)));
  }

  Future<void> _authenticate() => _run(isAuthAttempt: true, () async {
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
        : await _login(client);
    if (auth == null) return; // the code prompt was cancelled
    await widget.connection.saveSession(url: url, auth: auth);
    await widget.connection.fetchCapabilities();
    await _reconcileProfile(auth.user.displayName);
  });

  /// Password sign-in, plus the code when the account has two-factor sign-in
  /// on. Null when the code prompt is cancelled. A wrong code throws a 401
  /// [ServerException], which [_run] shows as the error; signing in again
  /// starts a fresh challenge.
  Future<AuthResult?> _login(VellumServerClient client) async {
    try {
      return await client.login(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on TwoFactorRequired catch (e) {
      final code = await _askTwoFactorCode();
      if (code == null) return null;
      return client.completeTwoFactor(challenge: e.challenge, code: code);
    }
  }

  /// Asks for the code from the authenticator app (or a recovery code).
  /// Null when the dialog is dismissed or left empty.
  Future<String?> _askTwoFactorCode() async {
    if (!mounted) return null;
    final l10n = L10n.of(context);
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.serverTwoFactorTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.serverTwoFactorBody),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              // Recovery codes have letters, so not a number-only keyboard.
              keyboardType: TextInputType.visiblePassword,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: InputDecoration(labelText: l10n.serverTwoFactorCode),
              onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.serverTwoFactorVerify),
          ),
        ],
      ),
    );
    final code = controller.text.trim();
    controller.dispose();
    return ok == true && code.isNotEmpty ? code : null;
  }

  /// Two names, one person — asks which to keep.
  ///
  /// The local profile and the server account were unrelated until now: you
  /// could be "Ana" here and signed in as bob@example.com, with nothing saying
  /// so. Personal-data sync then resolved the difference by whichever timestamp
  /// was newer, silently, and the thing that changed was your name and face.
  ///
  /// So it is asked once, at the moment the two first meet, in the same shape
  /// as "Resume where you left off?" — the app's existing answer to *two
  /// truths, don't guess*. After this the newest-wins rule is fine, because the
  /// two are known to be the same person.
  Future<void> _reconcileProfile(String accountName) async {
    final profile = widget.profile;
    if (profile == null || !mounted) return;
    final local = profile.name.trim();
    final remote = accountName.trim();
    // Nothing to ask when this device has no name yet, or they already agree.
    if (local.isEmpty || remote.isEmpty || local == remote) {
      if (local.isEmpty && remote.isNotEmpty) {
        await profile.adopt(name: remote);
      }
      return;
    }

    final l10n = L10n.of(context);
    final keepLocal = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.serverWhichNameTitle),
        content: Text(l10n.serverWhichNameBody(local, remote)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.serverUseName(remote)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.serverKeepName(local)),
          ),
        ],
      ),
    );
    if (keepLocal == null) return; // dismissed — decide nothing, ask next time
    if (!keepLocal) {
      await profile.adopt(name: remote);
    } else {
      // Keeping the local name means it is the newer truth; the next sync
      // publishes it. Re-stamping is what makes that so.
      await profile.save(name: local, email: profile.email);
    }
  }

  /// The main Sync action — wrapped (Android only) in a foreground service
  /// and a status-bar progress notification, so a sync survives the app
  /// being backgrounded instead of dying mid-request with a DNS failure, and
  /// says so in the notification rather than only on a screen that may not
  /// be on screen any more. [SyncForegroundService.start]/[stop] are no-ops
  /// off Android; [_syncTray] checks the platform itself.
  ///
  /// [resultMessage] is set inside the wrapped action on success and read
  /// back out in `finally`, because [_run] swallows its own errors into
  /// [_error] rather than rethrowing — the two together are how this knows
  /// what the notification should say without [_run] having to change.
  Future<void> _syncNow() async {
    final l10n = L10n.of(context);
    await SyncForegroundService.start();
    _notifyingSync = true;
    await _syncTray.start();
    String? resultMessage;
    try {
      await _run(() async {
        final client = widget.connection.client;
        if (client == null) return;
        final report = await _sync.sync(
          client,
          cursor: widget.connection.syncCursor,
          onCursor: widget.connection.setSyncCursor,
          onProgress: _onProgress,
          scope: widget.settings.syncScope,
        );
        // Its own pass, after the guard is free, and only when opted in.
        // Failures here don't spoil an otherwise successful sync report.
        if (widget.settings.syncReadingPosition) {
          try {
            await _sync.syncReadingProgress(
              client,
              deviceId: widget.settings.deviceId,
              deviceLabel: widget.settings.deviceLabel,
              cursor: widget.connection.readingCursor,
              onCursor: widget.connection.setReadingCursor,
            );
          } catch (_) {
            // Offline, or a server without the endpoint.
          }
        }
        final n = report.issues.length;
        final changed = report.pulled + report.pushed;
        final msg = changed == 0 && !report.hasIssues
            ? l10n.serverUpToDate
            : report.hasIssues
            ? l10n.serverSyncResultIssues(
                report.pulled,
                report.pushed,
                l10n.syncIssues(n),
              )
            : l10n.serverSyncResult(report.pulled, report.pushed);
        resultMessage = msg;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(
            content: Text(msg),
            action: report.hasIssues
                ? SnackBarAction(
                    label: l10n.serverDetails,
                    onPressed: () => _showIssues(report.issues),
                  )
                : null,
          ),
        );
      });
    } finally {
      await _syncTray.finish(resultMessage ?? _error ?? l10n.syncFinished);
      _notifyingSync = false;
      await SyncForegroundService.stop();
    }
  }

  Future<void> _pull() => _run(() async {
    final client = widget.connection.client;
    if (client == null) return;
    final report = await _sync.pull(
      client,
      cursor: widget.connection.syncCursor,
      onCursor: widget.connection.setSyncCursor,
      onProgress: _onProgress,
    );
    _showReport(true, report.pulled, report);
  });

  Future<void> _push() => _run(() async {
    final client = widget.connection.client;
    if (client == null) return;
    final report = await _sync.push(client, onProgress: _onProgress);
    _showReport(false, report.pushed, report);
  });

  /// Certificate status + import control for [url], shown for https URLs (a
  /// self-signed server needs its certificate imported before the handshake can
  /// succeed). Used on both the sign-in screen and the connected view, so a
  /// rotated certificate can be re-imported without disconnecting.
  Widget _certRow(ThemeData theme, String url) {
    final l10n = L10n.of(context);
    final isHttps = ServerConnection.normalizeUrl(url).startsWith('https://');
    if (!isHttps) return const SizedBox.shrink();
    final pem = widget.connection.certFor(url);
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
                  ? l10n.serverCertNone
                  : l10n.serverCertTrusted(_shortFingerprint(fp!)),
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => _importCert(url),
            child: Text(
              pem == null ? l10n.serverCertImport : l10n.serverCertChange,
            ),
          ),
        ],
      ),
    );
  }

  /// True when the entered URL is plain http to a non-loopback host on Android,
  /// which the app's network_security_config blocks — so logging in would fail
  /// with an opaque socket error. Used to disable Log in with a clear reason.
  bool _httpBlockedOnAndroid(ThemeData theme) {
    if (theme.platform != TargetPlatform.android) return false;
    final url = ServerConnection.normalizeUrl(_url.text);
    if (!url.startsWith('http://')) return false;
    const loopback = {'localhost', '127.0.0.1', '10.0.2.2', '10.0.3.2', '::1'};
    return !loopback.contains(Uri.tryParse(url)?.host ?? '');
  }

  /// First few groups of a fingerprint, enough to eyeball against the server's.
  String _shortFingerprint(String fp) {
    final groups = fp.split(':');
    return groups.length <= 6 ? fp : '${groups.take(6).join(':')}…';
  }

  /// Import the server's certificate for [url] — pasted as PEM or read from a
  /// chosen `.pem`/`.crt` file. Passing an empty result forgets it.
  Future<void> _importCert(String url) async {
    final l10n = L10n.of(context);
    final controller = TextEditingController(
      text: widget.connection.certFor(url) ?? '',
    );
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        String? err;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(l10n.serverCertTitle),
            content: SizedBox(
              width: _dialogWidth(context, 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.serverCertBody),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final group = XTypeGroup(
                          label: l10n.serverCertGroup,
                          extensions: const ['pem', 'crt', 'cer'],
                        );
                        final file = await openFile(
                          acceptedTypeGroups: [group],
                        );
                        if (file != null) {
                          controller.text = await File(
                            file.path,
                          ).readAsString();
                          setLocal(() => err = null);
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.serverCertChoose),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    maxLines: 6,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText:
                          '-----BEGIN CERTIFICATE-----', // i18n-ignore: PEM marker
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      err!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (widget.connection.certFor(url) != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: Text(l10n.serverCertRemove),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final pem = controller.text.trim();
                  if (pem.isEmpty) {
                    Navigator.pop(context, '');
                    return;
                  }
                  if (fingerprintOf(pem) == null) {
                    setLocal(() => err = l10n.serverCertBad);
                    return;
                  }
                  Navigator.pop(context, pem);
                },
                child: Text(l10n.serverCertTrust),
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
      appBar: AppBar(title: Text(L10n.of(context).serverTitle)),
      body: ListenableBuilder(
        listenable: widget.connection,
        builder: (context, _) => widget.connection.isConnected
            ? _buildConnected(context)
            : _buildSignIn(context),
      ),
    );
  }

  /// Honesty banner shown when the session token had to be stored unencrypted
  /// (no OS keyring). Dismissable — tapping "Got it" records the acknowledgement
  /// so it isn't shown again until a new insecure session re-arms it.
  Widget _insecureTokenNotice(ThemeData theme, ServerConnection conn) {
    final l10n = L10n.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lock_open,
                  size: 18,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.serverInsecureTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.serverInsecureBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: conn.dismissInsecureTokenWarning,
                child: Text(l10n.serverGotIt),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when `capabilities.sync_protocol` is newer than this app build
  /// knows (`kKnownSyncProtocol`) — one clear line rather than letting sync
  /// silently miss whatever the protocol bump was for.
  Widget _newerServerNotice(ThemeData theme) {
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                L10n.of(context).serverNewer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnected(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final conn = widget.connection;
    final caps = conn.capabilities;
    return ListView(
      padding: pageInsets(context, EdgeInsets.all(24)),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: Text(conn.email),
            subtitle: Text(
              caps == null
                  ? conn.baseUrl
                  : l10n.serverVersionLine(conn.baseUrl, caps.serverVersion),
            ),
            trailing: conn.isMaster
                ? Chip(
                    label: Text(l10n.serverMaster),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  )
                : null,
          ),
        ),
        // One-time honesty notice: the OS secure store was unavailable, so the
        // session token is sitting in plaintext preferences (L2).
        if (conn.shouldWarnInsecureToken) _insecureTokenNotice(theme, conn),
        // The one real consequence of the capability handshake today: a
        // server on a newer sync protocol than this app build understands
        // should say so plainly rather than have sync silently miss whatever
        // changed (plan 5 #6). Feature-gating individual sync phases is left
        // for whichever future item first ships an optional one — nothing
        // the app does today is actually optional yet.
        if (caps?.isNewerThanApp ?? false) _newerServerNotice(theme),
        // Lets a rotated/regenerated server certificate be re-imported without
        // disconnecting (an https server only).
        _certRow(theme, conn.baseUrl),
        const SizedBox(height: 24),
        Text(l10n.serverSyncHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.serverSyncBlurb),
        const SizedBox(height: 12),
        Row(
          children: [
            // Listens to the *service*, not only to this page. The launch sync
            // starts before this screen exists and is silent by design, so a
            // button that watched `_busy` alone looked idle mid-sync, was
            // pressed, and answered "a sync is already in progress" for a sync
            // the reader never saw start. Now it says what is true.
            ValueListenableBuilder<bool>(
              valueListenable: _sync.running,
              builder: (context, syncing, _) {
                final busy = _busy || syncing;
                return FilledButton.icon(
                  onPressed: busy ? null : _syncNow,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(busy ? l10n.serverSyncing : l10n.serverSyncNow),
                );
              },
            ),
            const SizedBox(width: 12),
            // What syncs is a decision, not a setting to hunt for: it belongs
            // beside the button that acts on it (next features #8).
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SyncScopePage(
                    settings: widget.settings,
                    repository: widget.repository,
                    connection: widget.connection,
                  ),
                ),
              ),
              icon: const Icon(Icons.tune),
              label: Text(l10n.serverWhatSyncs),
            ),
          ],
        ),
        if (!widget.settings.syncScope.isEverything)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.serverNotSyncing(
                widget.settings.syncScope.excludedOf(l10n).join(', '),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          title: Text(l10n.serverAdvanced, style: theme.textTheme.titleSmall),
          subtitle: Text(l10n.serverAdvancedNote),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pull,
                  icon: const Icon(Icons.download),
                  label: Text(l10n.serverPullLibrary),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _push,
                  icon: const Icon(Icons.upload),
                  label: Text(l10n.serverPushBooks),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
          if (_phase != null) ...[
            const SizedBox(height: 6),
            Text(_phase!.labelOf(l10n), style: theme.textTheme.bodySmall),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Text(l10n.serverSharingHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.serverSharingBlurb),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SharingPage(connection: widget.connection),
                  ),
                ),
          icon: const Icon(Icons.group_outlined),
          label: Text(l10n.serverManageSharing),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => widget.connection.disconnect(),
          icon: const Icon(Icons.logout),
          label: Text(l10n.serverDisconnect),
        ),
      ],
    );
  }

  Widget _buildSignIn(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return ListView(
      padding: pageInsets(context, EdgeInsets.all(24)),
      children: [
        Text(
          _registerMode ? l10n.serverSignInRegister : l10n.serverSignInTitle,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _registerMode ? l10n.serverRegisterBlurb : l10n.serverSignInBlurb,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          onChanged: (value) {
            setState(() {});
            _probeMail(value);
          },
          decoration: InputDecoration(
            labelText: l10n.serverAddressLabel,
            hintText: 'https://library.example.com', // i18n-ignore: a URL
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
                  _httpBlockedOnAndroid(theme)
                      ? l10n.serverHttpBlocked
                      : l10n.serverHttpCleartext,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
        _certRow(theme, _url.text),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: l10n.serverEmail,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_registerMode) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _displayName,
            decoration: InputDecoration(
              labelText: l10n.serverDisplayName,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          onSubmitted: (_) =>
              (_busy || _httpBlockedOnAndroid(theme)) ? null : _authenticate(),
          decoration: InputDecoration(
            labelText: l10n.serverPassword,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: (_busy || _httpBlockedOnAndroid(theme))
              ? null
              : _authenticate,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _registerMode ? l10n.serverCreateAccount : l10n.serverLogIn,
                ),
        ),
        // Offered only when the server says it can send mail (plan 5 #31): a
        // "Forgot password?" link on a LAN server with no SMTP would be a
        // button that can only fail.
        if (!_registerMode && _mailAvailable)
          TextButton(
            onPressed: _busy ? null : _forgotPassword,
            child: Text(l10n.serverForgot),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _registerMode = !_registerMode;
                  _error = null;
                }),
          child: Text(
            _registerMode ? l10n.serverHaveAccount : l10n.serverNewServer,
          ),
        ),
      ],
    );
  }
}
