import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// The volume keys as page turns (Android, opt-in in the reader's settings).
///
/// The keys are claimed natively, in `MainActivity.dispatchKeyEvent`, and only
/// while a reader that wants them is open; everywhere else they change the
/// volume as usual. A reader owns one of these: [sync] it with the setting
/// whenever that changes, and [dispose] it when the page goes.
class VolumeKeys {
  VolumeKeys({
    required this.isActive,
    required this.onStep,
    MethodChannel? channel,
    bool? supported,
  })  : _channel = channel ?? const MethodChannel(channelName),
        supported = supported ?? Platform.isAndroid;

  static const channelName = 'app.vellum.Vellum/volume_keys';

  /// Whether this reader is the one on top: a dialog or another page over it
  /// should not have its book turn underneath.
  final bool Function() isActive;

  /// +1 forward, -1 back. Volume down reads on, as on a physical e-reader.
  final void Function(int delta) onStep;

  final MethodChannel _channel;

  /// False off Android, where there is nothing to claim.
  final bool supported;

  bool _on = false;

  /// The instance whose handler is installed, so a page closing after the
  /// next one opened does not take the next one's handler away.
  static VolumeKeys? _owner;

  /// Turns the interception on or off to match [wanted].
  Future<void> sync(bool wanted) async {
    if (!supported || wanted == _on) return;
    _on = wanted;
    try {
      if (wanted) {
        _owner = this;
        _channel.setMethodCallHandler(_handle);
        await _channel.invokeMethod<void>('enable');
      } else {
        _release();
        await _channel.invokeMethod<void>('disable');
      }
    } on MissingPluginException {
      // A build without the native half: the keys just keep their old job.
    }
  }

  void _release() {
    if (_owner == this) {
      _owner = null;
      _channel.setMethodCallHandler(null);
    }
  }

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'key' || !isActive()) return;
    onStep(call.arguments == 'up' ? -1 : 1);
  }

  Future<void> dispose() async {
    if (!_on) return;
    _on = false;
    final owned = _owner == this;
    _release();
    // Only switch the native side off if no newer reader has taken over.
    if (!owned) return;
    try {
      await _channel.invokeMethod<void>('disable');
    } on MissingPluginException {
      // Nothing native to switch off.
    }
  }
}
