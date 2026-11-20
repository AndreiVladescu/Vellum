import 'package:material_ui/material_ui.dart';

import '../l10n/gen/app_localizations.dart';
import 'audiobook_player.dart';
import 'playback_host.dart';
import 'player_page.dart';

/// The strip above the shell's navigation that shows what is playing and
/// reopens the player — the way back to a book whose page was left while it
/// kept playing. Nothing (zero height) when no audiobook is loaded.
///
/// It is the shell's `bottomNavigationBar` (above the navigation bar on a
/// phone, alone on a rail or drawer layout), not a layer over the content, so
/// it never covers the last row of the shelf, and the floating buttons ride
/// above it.
class NowPlayingBar extends StatelessWidget {
  NowPlayingBar({super.key, PlaybackHost? host, this.padBottom = false})
      : host = host ?? PlaybackHost.instance;

  final PlaybackHost host;

  /// Whether to keep clear of the system's bottom bar. Off when a
  /// `NavigationBar` sits below, which does that itself.
  final bool padBottom;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        final player = host.player;
        final repository = host.repository;
        if (player == null || repository == null) return const SizedBox.shrink();
        return _Bar(host: host, player: player, padBottom: padBottom);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.host, required this.player, required this.padBottom});
  final bool padBottom;
  final PlaybackHost host;
  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final book = host.book;
    final repository = host.repository!;
    final cover = book == null ? null : repository.coverFileOf(book);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: SafeArea(
        top: false,
        bottom: padBottom,
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final chapter = player.currentChapter;
            final title = chapter >= 0
                ? (player.chapters[chapter].title?.trim().isNotEmpty ?? false
                    ? player.chapters[chapter].title!.trim()
                    : l10n.playerChapterNumber(chapter + 1))
                : '';
            final total = player.total.inMilliseconds;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlayerPage(
                        bookId: player.bookId,
                        repository: repository,
                        host: host),
                  )),
                  child: Tooltip(
                    message: l10n.nowPlayingOpen,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                      child: Row(
                        children: [
                          if (cover != null && cover.existsSync())
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(cover,
                                    height: 40, width: 28, fit: BoxFit.cover),
                              ),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Icon(Icons.headphones),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(book?.title ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall),
                                if (title.isNotEmpty)
                                  Text(title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.playerBack30,
                            icon: const Icon(Icons.replay_30),
                            onPressed: () => player.skip(const Duration(seconds: -30)),
                          ),
                          IconButton.filled(
                            tooltip:
                                player.playing ? l10n.playerPause : l10n.playerPlay,
                            icon: Icon(
                                player.playing ? Icons.pause : Icons.play_arrow),
                            onPressed: player.playing ? player.pause : player.play,
                          ),
                          IconButton(
                            tooltip: l10n.nowPlayingClose,
                            icon: const Icon(Icons.close),
                            onPressed: host.close,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                LinearProgressIndicator(
                  value: total <= 0
                      ? 0
                      : (player.position.inMilliseconds / total).clamp(0.0, 1.0),
                  minHeight: 2,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
