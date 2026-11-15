import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import 'read_aloud.dart';
import 'tts_engine.dart';

/// The player that floats over the page while a book is being read aloud:
/// back a sentence, play or pause, forward a sentence, stop.
class ReadAloudBar extends StatelessWidget {
  const ReadAloudBar({
    super.key,
    required this.readAloud,
    required this.foreground,
    required this.background,
  });

  final ReadAloud readAloud;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListenableBuilder(
      listenable: readAloud,
      builder: (context, _) {
        final controller = readAloud.controller;
        if (!controller.active) return const SizedBox.shrink();
        final style = IconButton.styleFrom(foregroundColor: foreground);
        return Material(
          color: background,
          elevation: 3,
          shape: StadiumBorder(
              side: BorderSide(color: foreground.withValues(alpha: 0.2))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  tooltip: l10n.ttsPreviousSentence,
                  style: style,
                  onPressed: () => controller.skip(-1),
                ),
                IconButton(
                  icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow),
                  tooltip: controller.playing ? l10n.ttsPause : l10n.ttsPlay,
                  style: style,
                  onPressed: controller.togglePause,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  tooltip: l10n.ttsNextSentence,
                  style: style,
                  onPressed: () => controller.skip(1),
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  tooltip: l10n.ttsStopReading,
                  style: style,
                  onPressed: controller.stop,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Speed and voice, for the reader's settings sheet. Both are remembered.
class ReadAloudSettingsSection extends StatelessWidget {
  const ReadAloudSettingsSection({super.key, required this.readAloud});

  final ReadAloud readAloud;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: readAloud,
      builder: (context, _) {
        // Nothing to set on a device that cannot speak; the action itself
        // explains why when it is chosen.
        if (readAloud.available != true) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(l10n.ttsSettingsTitle, style: theme.textTheme.labelLarge),
            Row(
              children: [
                SizedBox(width: 100, child: Text(l10n.ttsSpeed)),
                Expanded(
                  child: Slider(
                    value: readAloud.rate.clamp(ReadAloud.minRate, ReadAloud.maxRate),
                    min: ReadAloud.minRate,
                    max: ReadAloud.maxRate,
                    divisions: 15,
                    onChanged: readAloud.setRate,
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    l10n.ttsSpeedValue(readAloud.rate.toStringAsFixed(1)),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            if (readAloud.voices.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.ttsVoiceUnavailable,
                    style: theme.textTheme.bodySmall),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.ttsVoice),
                subtitle: Text(readAloud.voice == null
                    ? l10n.ttsVoiceAutomatic
                    : '${readAloud.voice!.name} (${readAloud.voice!.locale})'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickVoice(context),
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickVoice(BuildContext context) async {
    final l10n = L10n.of(context);
    // A sentinel for "automatic": `showDialog` returning null means dismissed.
    const automatic = TtsVoice('', '');
    final picked = await showDialog<TtsVoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.ttsVoice),
        children: [
          SizedBox(
            width: 360,
            height: 360,
            child: ListView(
              children: [
                RadioGroup<TtsVoice>(
                  groupValue: readAloud.voice ?? automatic,
                  onChanged: (v) => Navigator.pop(dialogContext, v),
                  child: Column(
                    children: [
                      RadioListTile<TtsVoice>(
                        value: automatic,
                        title: Text(l10n.ttsVoiceAutomatic),
                      ),
                      for (final voice in readAloud.voices)
                        RadioListTile<TtsVoice>(
                          value: voice,
                          title: Text(voice.name),
                          subtitle: Text(voice.locale),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await readAloud.setVoice(picked == automatic ? null : picked);
  }
}
