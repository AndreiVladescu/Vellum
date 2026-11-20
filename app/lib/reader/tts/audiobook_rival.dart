import 'package:flutter/foundation.dart';

import '../../audio/audiobook_player.dart';
import '../../audio/playback_host.dart';
import 'speech_session.dart';

/// The audiobook player as read aloud's [SpeechRival]: reads the app's
/// [PlaybackHost] and pauses its player, and changes nothing in `lib/audio`.
///
/// The host is looked up when first needed rather than in the constructor, so
/// a reader that never reads aloud never touches it.
class AudiobookRival implements SpeechRival {
  AudiobookRival([this._host]);

  PlaybackHost? _host;
  PlaybackHost get host => _host ??= PlaybackHost.instance;

  @override
  bool get playing => host.player?.playing ?? false;

  @override
  Future<void> pause() async => host.player?.pause();

  @override
  VoidCallback addStartListener(VoidCallback onStart) {
    final host = this.host;
    AudiobookPlayer? bound;
    var wasPlaying = false;

    void onPlayer() {
      final now = bound?.playing ?? false;
      if (now && !wasPlaying) onStart();
      wasPlaying = now;
    }

    // The host swaps its player when another book is opened.
    void rebind() {
      if (identical(bound, host.player)) return;
      bound?.removeListener(onPlayer);
      bound = host.player;
      wasPlaying = bound?.playing ?? false;
      bound?.addListener(onPlayer);
    }

    rebind();
    host.addListener(rebind);
    return () {
      host.removeListener(rebind);
      bound?.removeListener(onPlayer);
      bound = null;
    };
  }
}
