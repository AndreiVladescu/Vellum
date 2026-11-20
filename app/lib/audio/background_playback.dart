import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audio_handler.dart';
import 'audiobook_player.dart';

/// Hands a playing book to the OS's media session, and takes it back.
///
/// The session is started lazily, the first time something plays, so the app
/// starts as fast as before and a machine where it cannot start (no D-Bus
/// session, or an SMTC that fails to start on Windows) loses only the
/// system controls: playback itself is the [AudiobookPlayer]'s and goes on
/// while the app is open.
class BackgroundPlayback {
  /// [handlerFactory] replaces the real `AudioService.init`; for tests.
  BackgroundPlayback({Future<VellumAudioHandler?> Function(String channelName)? handlerFactory})
      : _factory = handlerFactory ?? _initAudioService;

  final Future<VellumAudioHandler?> Function(String channelName) _factory;
  Future<VellumAudioHandler?>? _handler;

  /// The session's handler once it has started, or null when it has not or
  /// cannot here.
  VellumAudioHandler? handler;

  /// Makes [player] what the system controls show and drive.
  Future<void> attach(
    AudiobookPlayer player, {
    required String channelName,
    required String title,
    String? author,
    Uri? artUri,
    required String Function(int number) untitledChapter,
  }) async {
    final h = handler ??= await (_handler ??= _factory(channelName));
    h?.attach(player,
        title: title, author: author, artUri: artUri, untitledChapter: untitledChapter);
  }

  /// Takes the book off the system controls.
  void detach() => handler?.detach();

  static Future<VellumAudioHandler?> _initAudioService(String channelName) async {
    if (!VellumAudioHandler.supportedHere) return null;
    try {
      return await AudioService.init(
        builder: VellumAudioHandler.new,
        config: AudioServiceConfig(
          androidNotificationChannelId: 'app.vellum.Vellum.playback',
          androidNotificationChannelName: channelName,
          androidNotificationIcon: 'drawable/ic_stat_audio',
          // Swipeable when paused, as every media notification is. A paused
          // player's notification going away costs nothing: the position was
          // saved on the pause, and the mini bar resumes.
          androidStopForegroundOnPause: true,
          fastForwardInterval: const Duration(seconds: 30),
          rewindInterval: const Duration(seconds: 30),
        ),
      );
    } catch (e) {
      debugPrint('Media session unavailable: $e');
      return null;
    }
  }
}
