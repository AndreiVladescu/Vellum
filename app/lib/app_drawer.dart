import 'package:flutter/material.dart';

import 'app_version.dart';
import 'l10n/gen/app_localizations.dart';
import 'widgets/adaptive.dart';
import 'widgets/page_insets.dart';

import 'account/account_page.dart';
import 'account/profile_avatar.dart';
import 'account/user_profile.dart';
import 'data/library_repository.dart';
import 'dedupe/duplicates_page.dart';
import 'import/folder_import_page.dart';
import 'stats/insights_page.dart';
import 'stats/library_stats_page.dart';
import 'loans/loans_page.dart';
import 'server/connection_store.dart';
import 'server/server_page.dart';
import 'server/sync_service.dart';
import 'settings/app_settings.dart';
import 'settings/preferences_page.dart';
import 'loans/due_dates.dart';
import 'shelf/series_page.dart';
import 'wishlist/wishlist_page.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.profile,
    required this.settings,
    required this.connection,
    required this.repository,
    required this.sync,
    this.section,
    this.onSection,
  });

  final UserProfileStore profile;
  final AppSettingsStore settings;
  final ServerConnection connection;
  final LibraryRepository repository;
  final SyncService sync;

  /// The shell's selected section, and how to change it — given only for the
  /// *permanent* drawer of a wide window ([WindowSize.expanded]).
  ///
  /// There the drawer is the navigation: no bottom bar, no rail, so it lists
  /// both sections itself. It also never pops — the modal drawer closes itself
  /// with `Navigator.pop`, and from a drawer that is part of the page that pop
  /// would close the page instead.
  final int? section;
  final ValueChanged<int>? onSection;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  UserProfileStore get profile => widget.profile;
  AppSettingsStore get settings => widget.settings;
  ServerConnection get connection => widget.connection;
  LibraryRepository get repository => widget.repository;
  SyncService get sync => widget.sync;

  bool get _permanent => widget.onSection != null;

  // Opened once, not per build. A modal drawer is built only while it is open,
  // but the permanent one is rebuilt with the shell — every search keystroke —
  // and a fresh `.watch()` each time would re-run both queries on every one.
  late final Stream<List<LoanEntry>> _loans = repository.watchAllLoans();
  late final Stream<int> _wishlistCount = repository.wishlist.watchCount();

  /// Closes the modal drawer before going anywhere; the permanent one has
  /// nothing to close.
  void _close(BuildContext context) {
    if (!_permanent) Navigator.of(context).pop();
  }

  void _openServer(BuildContext context) {
    _close(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ServerPage(
        connection: connection,
        repository: repository,
        sync: sync,
        settings: settings,
        profile: profile,
      ),
    ));
  }

  void _openPreferences(BuildContext context) {
    _close(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PreferencesPage(
              settings: settings,
              repository: repository,
              connection: connection,
              sync: sync,
            ),
      ),
    );
  }

  void _openLoans(BuildContext context) {
    _close(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          LoansPage(repository: repository, connection: connection),
    ));
  }

  void _openFolderImport(BuildContext context) {
    _close(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FolderImportPage(
        repository: repository,
        settings: settings,
      ),
    ));
  }

  void _openDuplicates(BuildContext context) {
    _close(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DuplicatesPage(repository: repository),
    ));
  }

  void _openSeries(BuildContext context) {
    _close(context);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SeriesPage(repository: repository),
    ));
  }

  void _openWishlist(BuildContext context) {
    _close(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WishlistPage(
        repository: repository,
        settings: settings,
        connection: connection,
      ),
    ));
  }

  void _openInsights(BuildContext context) {
    _close(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InsightsPage(repository: repository, settings: settings),
    ));
  }

  void _openAccount(BuildContext context) {
    _close(context);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AccountPage(profile: profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      // Square and flat when it is part of the page: the rounded edge and the
      // shadow are what say "this is on top of something", and it isn't.
      elevation: _permanent ? 0 : null,
      shape: _permanent ? const RoundedRectangleBorder() : null,
      child: ListView(
        padding: pageInsets(context, EdgeInsets.zero),
        children: [
          ListenableBuilder(
            // Both: the header shows the profile's name and photo *and* the
            // account it syncs as, so connecting has to repaint it too.
            listenable: Listenable.merge([profile, connection]),
            builder: (context, _) => UserAccountsDrawerHeader(
              currentAccountPicture: ProfileAvatar(profile: profile, radius: 30),
              accountName:
                  Text(profile.isSet
                      ? profile.name
                      : L10n.of(context).drawerSetUpProfile),
              // Your own email — the one the Account page edits. Connecting
              // used to replace it with the account's, which left the profile
              // email edited on one screen and shown nowhere; the account you
              // sync as is on the *Library server* tile below, so both are
              // still readable at once. Falls back to the account's when the
              // profile has no email, rather than leaving the line blank.
              accountEmail: Text(
                profile.email.isNotEmpty
                    ? profile.email
                    : (connection.isConnected
                        ? connection.email
                        : L10n.of(context).drawerLocalLibrary),
              ),
              onDetailsPressed: () => _openAccount(context),
            ),
          ),
          if (_permanent) ...[
            // The same two sections, and the same icons, as the bottom bar and
            // the rail they stand in for.
            ListTile(
              leading: Icon(
                  widget.section == 0 ? Icons.menu_book : Icons.menu_book_outlined),
              title: Text(L10n.of(context).drawerMyShelf),
              selected: widget.section == 0,
              onTap: () => widget.onSection!(0),
            ),
            ListTile(
              leading: Icon(widget.section == 1
                  ? Icons.grid_view_rounded
                  : Icons.grid_view_outlined),
              title: Text(L10n.of(context).physicalLibraries),
              selected: widget.section == 1,
              onTap: () => widget.onSection!(1),
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.shelves),
              title: Text(L10n.of(context).drawerMyShelf),
              selected: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(L10n.of(context).drawerLoans),
            // The count of loans wanting attention, so an overdue book is
            // visible without opening the page. Everything else on this
            // screen you go looking for; an overdue loan is the one thing
            // that should come and find you.
            trailing: StreamBuilder<List<LoanEntry>>(
              stream: _loans,
              builder: (context, snapshot) {
                final needing = [
                  for (final e in snapshot.data ?? const <LoanEntry>[])
                    if (LoanDue.urgencyOf(e.loan).needsAttention) e,
                ].length;
                if (needing == 0) return const SizedBox.shrink();
                return Text(
                  '$needing',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                );
              },
            ),
            onTap: () => _openLoans(context),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(L10n.of(context).importFolder),
            onTap: () => _openFolderImport(context),
          ),
          StreamBuilder<int>(
            stream: _wishlistCount,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return ListTile(
                leading: const Icon(Icons.bookmark_border),
                title: Text(L10n.of(context).drawerWishlist),
                trailing: count == 0 ? null : Text('$count'), // i18n-ignore
                onTap: () => _openWishlist(context),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.format_list_numbered),
            title: Text(L10n.of(context).drawerSeries),
            onTap: () => _openSeries(context),
          ),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: Text(L10n.of(context).drawerFindDuplicates),
            onTap: () => _openDuplicates(context),
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: Text(L10n.of(context).drawerInsights),
            onTap: () => _openInsights(context),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: Text(L10n.of(context).libraryStatsTitle),
            onTap: () {
              _close(context);
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => LibraryStatsPage(db: repository.db),
              ));
            },
          ),
          ListenableBuilder(
            listenable: connection,
            builder: (context, _) => ListTile(
              leading: Icon(connection.isConnected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_outlined),
              title: Text(L10n.of(context).drawerLibraryServer),
              subtitle: Text(connection.isConnected
                  ? L10n.of(context).drawerConnectedAs(connection.email)
                  : L10n.of(context).drawerNotConnected),
              onTap: () => _openServer(context),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(L10n.of(context).drawerPreferences),
            onTap: () => _openPreferences(context),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(L10n.of(context).drawerAccount),
            onTap: () => _openAccount(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(L10n.of(context).drawerAbout),
            onTap: () async {
              _close(context);
              // Read from the package itself rather than typed in here: this
              // line said 0.1.0 through eleven releases, because a number
              // written twice is a number that stops agreeing with itself.
              final version = await appVersion();
              if (!context.mounted) return;
              final l10n = L10n.of(context);
              showAboutDialog(
                context: context,
                applicationName: 'Vellum', // i18n-ignore: brand name
                applicationVersion: version,
                applicationIcon:
                    Image.asset('assets/logo.png', width: 48, height: 48),
                children: [Text(l10n.drawerAboutBlurb)],
              );
            },
          ),
        ],
      ),
    );
  }
}
