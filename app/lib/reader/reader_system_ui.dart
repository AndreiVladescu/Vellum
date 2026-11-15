import 'dart:io';

import 'package:flutter/services.dart';

/// Android's system bars belong to the reader, not the app.
///
/// The shelf and every other page draw edge to edge with the bars visible (the
/// Scaffold insets itself); only while a book is open do the bars hide, so the
/// page gets the whole screen. Opening the reader calls [enter] and closing it
/// calls [leave]. Desktop keeps its window chrome, so both are no-ops there.
class ReaderSystemUi {
  const ReaderSystemUi._();

  static void enter() {
    if (!Platform.isAndroid) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  static void leave() {
    if (!Platform.isAndroid) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
