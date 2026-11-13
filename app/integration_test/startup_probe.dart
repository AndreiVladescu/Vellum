// The profiling run's cold-start half (docs/PERFORMANCE.md, "The profiling
// run"). Not a test: an app entry point that runs the real `main()` and times
// it from the outside in, built and launched by tool/perf_run.sh:
//
//   flutter build linux --profile -t integration_test/startup_probe.dart
//
// It prints one line, `VELLUM_PERF_STARTUP {json}`, and (on a desktop) exits:
//
//   dart_main_ms              process start to the first line of Dart
//   first_frame_ms            ...to the first frame (the shelf, still empty)
//   first_shelf_frame_ms      ...to the first frame with books on it, built
//   first_shelf_raster_ms     ...and on screen (rasterised), when the engine's
//                             frame timings can be matched up
//   rss_mb_at_shelf / rss_mb_settled (4 s later, once start-up work is done)
//
// "Process start" is the launch time the run passes in VELLUM_PERF_LAUNCHED_AT
// (microseconds since the epoch, taken just before exec), or else the process
// start time from /proc — which is all an Android launch can offer, at 10 ms
// resolution.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:vellum/main.dart' as app;
import 'package:vellum/shelf/shelf_view.dart';

import 'perf_support.dart';

Future<void> main() async {
  final mainMono = Timeline.now;
  final mainWall = DateTime.now().microsecondsSinceEpoch;
  final launched =
      int.tryParse(Platform.environment['VELLUM_PERF_LAUNCHED_AT'] ?? '');
  final ageAtMain = launched != null ? mainWall - launched : _processAge();
  final startMono = mainMono - ageAtMain;

  final desktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  if (desktop &&
      !(Platform.environment['XDG_DATA_HOME'] ?? '').contains('vellum-perf')) {
    stderr.writeln('startup_probe: refusing to start outside a profiling '
        'directory (see tool/perf_run.sh)');
    exit(2);
  }

  WidgetsFlutterBinding.ensureInitialized();
  final timings = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  final shelf = Completer<void>();
  int? firstFrame;
  int? shelfFrame;
  var frames = 0;
  void check(Duration _) {
    frames++;
    firstFrame ??= Timeline.now;
    if (_showsASpine()) {
      shelfFrame = Timeline.now;
      shelf.complete();
    } else {
      SchedulerBinding.instance.addPostFrameCallback(check);
    }
  }

  SchedulerBinding.instance.addPostFrameCallback(check);
  unawaited(app.main());

  await shelf.future.timeout(const Duration(seconds: 60));
  final rssAtShelf = rssMb();
  await Future<void>.delayed(const Duration(seconds: 4));

  // The frame whose build the post-frame callback above ran after: the last
  // one to start building before the callback saw the spines.
  FrameTiming? shown;
  for (final t in timings) {
    final start = t.timestampInMicroseconds(FramePhase.buildStart);
    if (start <= shelfFrame! &&
        (shown == null ||
            start > shown.timestampInMicroseconds(FramePhase.buildStart))) {
      shown = t;
    }
  }
  double ms(int micros) => (micros / 100).roundToDouble() / 10;
  final rasterAt = shown?.timestampInMicroseconds(FramePhase.rasterFinish);
  final result = {
    'dart_main_ms': ms(ageAtMain),
    'first_frame_ms': ms(firstFrame! - startMono),
    'first_shelf_frame_ms': ms(shelfFrame! - startMono),
    // A frame's raster finishing more than a second after it was built means
    // the two clocks are not the same clock; report nothing rather than that.
    if (rasterAt != null && (rasterAt - shelfFrame!).abs() < 1000000)
      'first_shelf_raster_ms': ms(rasterAt - startMono),
    'frames_before_shelf': frames - 1,
    'rss_mb_at_shelf': (rssAtShelf * 10).roundToDouble() / 10,
    'rss_mb_settled': (rssMb() * 10).roundToDouble() / 10,
    ...imageCacheNow(),
    'launch_clock': launched != null ? 'env' : 'proc',
  };
  // A plain print: on Android it lands in logcat, where the run reads it.
  // ignore: avoid_print
  print('VELLUM_PERF_STARTUP ${jsonEncode(result)}');
  if (desktop) exit(0);
}

/// Microseconds since this process started, from /proc (Linux and Android):
/// `/proc/uptime` minus the start time in `/proc/self/stat`, both measured from
/// boot. Clock ticks are 100 a second on every kernel this runs on.
int _processAge() {
  try {
    final stat = File('/proc/self/stat').readAsStringSync();
    // Field 22, counted after the command name, which may itself hold spaces.
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    final startTicks = int.parse(fields[19]);
    final uptime = double.parse(
      File('/proc/uptime').readAsStringSync().split(' ').first,
    );
    return ((uptime - startTicks / 100) * 1e6).round();
  } catch (_) {
    return 0;
  }
}

/// Whether the tree holds a spine yet — the shelf, rather than the empty
/// "no books" page it shows until the library's first query answers.
bool _showsASpine() {
  var found = false;
  void visit(Element e) {
    if (found) return;
    if (e.widget is BookSpine) {
      found = true;
      return;
    }
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}
