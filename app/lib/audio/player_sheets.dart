import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import 'attach_audio.dart' show formatAudioTime;
import 'audiobook_player.dart';
import 'playback_options.dart';

/// The speed and sleep-timer sheets of the player page. Both read and drive
/// the [AudiobookPlayer] and rebuild as it changes, so the sleep sheet's
/// countdown is live and a speed set from the notification shows here.

Future<void> showSpeedSheet(BuildContext context, AudiobookPlayer player) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _SpeedSheet(player: player),
    );

Future<void> showSleepSheet(BuildContext context, AudiobookPlayer player) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SleepSheet(player: player),
    );

class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet({required this.player});
  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: player,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.playerSpeedTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Center(
                child: Text(formatSpeed(player.speed, locale: l10n.localeName),
                    style: theme.textTheme.headlineMedium),
              ),
              Slider(
                min: minSpeed,
                max: maxSpeed,
                divisions: ((maxSpeed - minSpeed) / speedStep).round(),
                value: player.speed,
                label: formatSpeed(player.speed, locale: l10n.localeName),
                onChanged: player.setSpeed,
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in speedPresets)
                    ChoiceChip(
                      label: Text(formatSpeed(preset, locale: l10n.localeName)),
                      selected: (player.speed - preset).abs() < 0.001,
                      onSelected: (_) => player.setSpeed(preset),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(l10n.playerSpeedNote, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleepSheet extends StatelessWidget {
  const _SleepSheet({required this.player});
  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    void choose(VoidCallback start) {
      start();
      Navigator.pop(context);
    }

    return SafeArea(
      child: ListenableBuilder(
        listenable: player,
        builder: (context, _) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (player.sleepActive)
                ListTile(
                  leading: const Icon(Icons.bedtime),
                  title: Text(player.sleepAtChapterEnd
                      ? l10n.playerSleepAtChapterEnd
                      : l10n.playerSleepIn(
                          formatAudioTime(player.sleepRemaining!))),
                  trailing: TextButton(
                    onPressed: () => choose(player.cancelSleep),
                    child: Text(l10n.playerSleepTurnOff),
                  ),
                ),
              for (final minutes in sleepMinutes)
                ListTile(
                  title: Text(l10n.playerSleepMinutes(minutes)),
                  onTap: () => choose(() => player.sleepFor(Duration(minutes: minutes))),
                ),
              ListTile(
                title: Text(l10n.playerSleepEndOfChapter),
                onTap: () => choose(player.sleepAtEndOfChapter),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(l10n.playerSleepNote, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
