import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import 'audiobook_player.dart';

/// The OS's view of the player: a media session (notification, lock screen,
/// headset and Bluetooth buttons on Android; Now Playing on macOS; MPRIS on
/// Linux) that **drives an [AudiobookPlayer]** and mirrors its state.
///
/// Why `audio_service` and not `just_audio_background`: the latter owns the
/// `AudioPlayer` and describes a playlist of `MediaItem`s, so the notification
/// would show one *part* at a time and its seek bar would span only that part.
/// Vellum plays one file at a time and keeps its own timeline over the parts
/// ([PartTimeline]), so the session must be told about the whole book. A
/// handler that wraps our controller does exactly that, and the buttons call
/// the same methods as the player page's.
///
/// The handler is a plain Dart object; nothing here touches a platform channel
/// except what `audio_service` does with `playbackState` and `mediaItem` once
/// `AudioService.init` has wrapped it, so a test can build one directly.
class VellumAudioHandler extends BaseAudioHandler {
  AudiobookPlayer? _player;
  String _bookTitle = '';
  String? _author;
  Uri? _artUri;
  String Function(int number) _untitled = (n) => '$n';

  int _publishedChapter = -2;
  Duration _publishedTotal = Duration.zero;
  bool? _publishedPlaying;
  double? _publishedSpeed;
  bool? _publishedEnded;
  Duration _publishedAt = Duration.zero;
  DateTime _publishedTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// How the book is described, and the one the buttons now act on.
  AudiobookPlayer? get player => _player;

  /// Points the session at [player]. A previous one is let go (not disposed:
  /// it belongs to the `PlaybackHost`).
  void attach(
    AudiobookPlayer player, {
    required String title,
    String? author,
    Uri? artUri,
    required String Function(int number) untitledChapter,
  }) {
    detach();
    _player = player;
    _bookTitle = title;
    _author = author;
    _artUri = artUri;
    _untitled = untitledChapter;
    _publishedChapter = -2;
    _publishedPlaying = null;
    player.addListener(_onPlayerChanged);
    _publish(force: true);
  }

  /// Lets the player go and shows nothing.
  void detach() {
    _player?.removeListener(_onPlayerChanged);
    _player = null;
    playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
  }

  String _chapterTitle(AudiobookPlayer p, int index) {
    final title = p.chapters[index].title?.trim();
    return title == null || title.isEmpty ? _untitled(index + 1) : title;
  }

  void _onPlayerChanged() => _publish();

  /// Pushes the player's state to the session, only when something the
  /// session cares about changed. The player notifies on every position tick
  /// (about five a second); the session extrapolates the position itself from
  /// the last update, its time and the speed, so it needs telling only about
  /// changes, including a jump (a seek) that the extrapolation would not
  /// predict.
  void _publish({bool force = false}) {
    final p = _player;
    if (p == null) return;
    final chapter = p.currentChapter;
    final total = p.total;
    final position = p.position;
    final now = DateTime.now();
    final expected = _publishedPlaying == true
        ? _publishedAt +
            Duration(
                microseconds: (now.difference(_publishedTime).inMicroseconds *
                        (_publishedSpeed ?? 1.0))
                    .round())
        : _publishedAt;
    final jumped = (position - expected).abs() > const Duration(seconds: 2);
    final changed = force ||
        jumped ||
        chapter != _publishedChapter ||
        total != _publishedTotal ||
        p.playing != _publishedPlaying ||
        p.speed != _publishedSpeed ||
        p.ended != _publishedEnded;
    if (!changed) return;

    if (force || chapter != _publishedChapter || total != _publishedTotal) {
      mediaItem.add(MediaItem(
        id: p.bookId,
        title: chapter >= 0 ? _chapterTitle(p, chapter) : _bookTitle,
        album: _bookTitle,
        artist: _author,
        duration: total,
        artUri: _artUri,
      ));
    }
    _publishedChapter = chapter;
    _publishedTotal = total;
    _publishedPlaying = p.playing;
    _publishedSpeed = p.speed;
    _publishedEnded = p.ended;
    _publishedAt = position;
    _publishedTime = now;

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        p.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [1, 2, 3],
      processingState:
          p.ended ? AudioProcessingState.completed : AudioProcessingState.ready,
      playing: p.playing,
      updatePosition: position,
      bufferedPosition: total,
      speed: p.speed,
      updateTime: now,
    ));
  }

  static const _jump = Duration(seconds: 30);

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<void> fastForward() async => _player?.skip(_jump);

  @override
  Future<void> rewind() async => _player?.skip(-_jump);

  @override
  Future<void> skipToNext() async => _player?.nextChapter();

  @override
  Future<void> skipToPrevious() async => _player?.previousChapter();

  @override
  Future<void> setSpeed(double speed) async => _player?.setSpeed(speed);

  /// Swiping the notification away, or "stop" from another controller: pause
  /// (which saves the position) and let the service go. The player stays with
  /// the app, so the mini bar still resumes it.
  @override
  Future<void> stop() async {
    await _player?.pause();
    _publishedPlaying = null; // so the next change is published afresh
    await super.stop();
  }

  /// The app was swiped from the recents while paused: nothing left to serve.
  @override
  Future<void> onTaskRemoved() async {
    if (_player?.playing != true) await stop();
  }

  /// Desktop has no task to remove.
  static bool get supportedHere =>
      Platform.isAndroid || Platform.isMacOS || Platform.isLinux;
}
