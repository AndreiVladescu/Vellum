import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../server/connection_store.dart';
import '../server/server_client.dart';
import 'layout_doc.dart';

/// Publishing a room to the server and fetching one back (plan 5 #47).
///
/// The interesting part is the **409**. A room is a composition, not a set of
/// independent rows: if this device and another both rearranged the shelves,
/// there is no merge that produces an arrangement either person made. So the
/// server refuses a publish whose `base_revision` is stale and the app asks the
/// human — overwrite theirs, or take theirs. Guessing here would silently throw
/// away somebody's afternoon.
class RoomPublisher {
  const RoomPublisher({required this.repository, required this.connection});

  final LibraryRepository repository;
  final ServerConnection connection;

  bool get available =>
      connection.isConnected &&
      (connection.capabilities?.hasFeature('layouts') ?? false);

  /// Serialises the room exactly as the editor draws it.
  Future<Map<String, dynamic>> _docFor(PhysicalEnvironment environment) async {
    final shelves = await repository.layout.watchShelves(environment.id).first;
    final placed = await repository.layout.watchPlacedBooks(environment.id).first;
    final props = await repository.layout.watchProps(environment.id).first;
    return buildLayoutDoc(
      environment: environment,
      shelves: shelves,
      placed: placed,
      props: props,
    );
  }

  /// Collects the room's books into a `Room: <name>` tag on the server.
  ///
  /// **This is how a room's books become visible to someone, and it rides the
  /// existing group/share RBAC rather than inventing a second path.** Sharing
  /// the room shares its *geometry*; sharing this tag — through the ordinary
  /// share UI — is what lets a viewer see titles and covers. Keeping the two
  /// separate is the reason the document carries no metadata in the first place.
  ///
  /// Refreshed rather than replaced: books added to the room since last time
  /// are added to the tag; nothing is removed, because a tag someone is already
  /// sharing should not quietly lose members behind their back.
  Future<String?> _refreshRoomGroup(
    VellumServerClient client,
    PhysicalEnvironment environment,
  ) async {
    final placed =
        await repository.layout.watchPlacedBooks(environment.id).first;
    if (placed.isEmpty) return null;
    final wanted = 'Room: ${environment.name}';

    final groups = await client.listGroups();
    final existing = groups.where((g) => g.name == wanted).firstOrNull;
    final groupId = existing?.id ?? (await client.createGroup(wanted)).id;

    for (final bookId in {for (final pb in placed) pb.book.id}) {
      try {
        await client.addBookToGroup(groupId, bookId);
      } catch (_) {
        // Already a member, or a book this account can't tag — neither is a
        // reason to fail the publish that just succeeded.
      }
    }
    return wanted;
  }

  /// Publishes, asking what to do on a conflict. Returns a sentence for the UI.
  ///
  /// [shareBooks] additionally collects the room's books into a `Room: <name>`
  /// tag; see [_refreshRoomGroup] for why that is a separate act.
  Future<String> publish(
    BuildContext context,
    PhysicalEnvironment environment, {
    bool shareBooks = false,
  }) async {
    final l10n = L10n.of(context);
    final client = connection.client;
    if (client == null) return l10n.publishRoomNotConnected;
    final doc = await _docFor(environment);
    String suffix = '';
    if (shareBooks) {
      final tag = await _refreshRoomGroup(client, environment);
      if (tag != null) suffix = ' ${l10n.publishRoomFooter(tag)}';
    }

    try {
      final result = await client.publishLayout(
        id: environment.id,
        name: environment.name,
        baseRevision: environment.serverRevision ?? 0,
        doc: doc,
      );
      await repository.layout.markPublished(environment.id, result.revision);
      return '${l10n.publishRoomPublished(environment.name, result.revision)}'
          '$suffix';
    } on ServerException catch (e) {
      if (e.statusCode != 409) return e.message;
      if (!context.mounted) return e.message;

      final choice = await _askConflict(context, environment.name);
      if (choice == null) return l10n.publishRoomUnpublished;
      if (choice == _Conflict.takeTheirs) {
        return fetch(l10n, environment.id, name: environment.name);
      }
      // Overwrite: re-read the server's revision and publish on top of it. The
      // user has been told plainly that this replaces the other arrangement.
      final current = await client.fetchLayout(environment.id);
      final forced = await client.publishLayout(
        id: environment.id,
        name: environment.name,
        baseRevision: current.revision,
        doc: doc,
      );
      await repository.layout.markPublished(environment.id, forced.revision);
      return '${l10n.publishRoomReplaced(forced.revision)}$suffix';
    }
  }

  /// Applies the server's copy over the local room.
  Future<String> fetch(L10n l10n, String layoutId, {String? name}) async {
    final client = connection.client;
    if (client == null) return l10n.publishRoomNotConnected;
    try {
      final remote = await client.fetchLayout(layoutId);
      final doc = remote.doc;
      if (doc == null) return l10n.publishRoomNoDocument;
      final parsed = parseLayoutDoc(doc);
      final skipped = await applyLayoutDoc(
        repository.db,
        parsed,
        revision: remote.revision,
      );
      final what = name ?? parsed.name;
      // Said plainly rather than swallowed: a room whose books haven't synced
      // yet renders with holes, and "3 books aren't here yet" is the difference
      // between a bug report and a sync.
      return skipped == 0
          ? l10n.publishRoomUpdated(what)
          : l10n.publishRoomUpdatedSkipped(skipped, what);
    } on LayoutDocException catch (e) {
      return e.messageOf(l10n);
    } on ServerException catch (e) {
      return e.message;
    }
  }

  Future<_Conflict?> _askConflict(BuildContext context, String name) {
    final l10n = L10n.of(context);
    return showDialog<_Conflict>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.publishRoomConflictTitle),
        content: Text(l10n.publishRoomConflictBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_Conflict.takeTheirs),
            child: Text(l10n.publishRoomTakeTheirs),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_Conflict.keepMine),
            child: Text(l10n.publishRoomReplaceMine),
          ),
        ],
      ),
    );
  }
}

enum _Conflict { keepMine, takeTheirs }
