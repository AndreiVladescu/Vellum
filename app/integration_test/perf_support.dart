// Shared by the profiling run's two halves (docs/PERFORMANCE.md, "The
// profiling run"): `perf_test.dart`, driven by `flutter drive`, and
// `startup_probe.dart`, built as an app of its own to time a cold start.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/seed_profiling.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/settings/book_face.dart';
import 'package:vellum/settings/spine_art.dart';
import 'package:vellum/stats/insights_range.dart';

/// Refuses to run anywhere but a library the profiling run made.
///
/// Both halves open the app's *real* data directory — that is the point, they
/// measure the real start-up path — so this is the one thing standing between
/// a mistyped command and the owner's library being profiled, padded with
/// seeded books, or (Android, empty library) seeded into. On Linux the run
/// points `XDG_DATA_HOME` at a directory of its own; anywhere, a library that
/// holds books not made by the seeder is left alone.
Future<void> guardProfilingLibrary(VellumDatabase db) async {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    final dataHome = Platform.environment['XDG_DATA_HOME'] ?? '';
    if (!dataHome.contains('vellum-perf')) {
      throw StateError(
        'Refusing to profile: XDG_DATA_HOME ($dataHome) is not a '
        'profiling directory. Run tool/perf_run.sh instead.',
      );
    }
  }
  final real = await db
      .customSelect(
        "SELECT COUNT(*) AS n FROM books WHERE id NOT LIKE 'seed-book-%'",
      )
      .getSingle();
  if (real.read<int>('n') > 0) {
    throw StateError(
      'Refusing to profile: this library holds books the profiling seeder '
      'did not make.',
    );
  }
}

/// Seeds the library in place when it is empty — the Android path, where the
/// run cannot copy a seeded directory into the app's private storage. Returns
/// whether it seeded.
Future<bool> seedIfEmpty(VellumDatabase db, Directory dataDir) async {
  final n = await db
      .customSelect('SELECT COUNT(*) AS n FROM books')
      .getSingle();
  if (n.read<int>('n') > 0) return false;
  final epub = await rootBundle.load('assets/samples/the-time-machine.epub');
  await seedProfilingLibrary(
    db,
    dataDir,
    // A phone-sized library: the shape is the same, the counts smaller so a
    // first launch on an emulator seeds in under a minute.
    spec: const ProfilingLibrary(books: 2000, sessions: 3000, placed: 300),
    epub: epub.buffer.asUint8List(epub.offsetInBytes, epub.lengthInBytes),
    sourcesDir: Directory(p.join(dataDir.path, 'perf-seed-sources')),
  );
  return true;
}

/// The preferences every profiling run starts from, whatever an earlier run
/// left behind: past the first-run sheet, spines on the shelf, both reading
/// goals set (so the insights page draws its goals card), default range.
Future<void> applyProfilingPreferences(AppSettingsStore settings) async {
  await settings.setHasSeenFirstRun(true);
  await settings.setBookFace(BookFace.spine);
  await settings.setSpineArt(SpineArt.coverSlice);
  await settings.setReadingGoals(books: 24, minutes: 30);
  await settings.setInsightsRange(InsightsRange.standard);
}

/// Resident set size, in MB.
double rssMb() => ProcessInfo.currentRss / (1 << 20);

double _round(double v) => (v * 10).roundToDouble() / 10;

/// The image cache as it stands, for the per-scenario memory columns.
Map<String, Object> imageCacheNow() {
  final cache = PaintingBinding.instance.imageCache;
  return {
    'image_cache_mb': _round(cache.currentSizeBytes / (1 << 20)),
    'image_cache_entries': cache.currentSize,
    'live_images': cache.liveImageCount,
  };
}

/// Frame timings straight from the engine (`FrameTiming`), alongside the
/// timeline summary `flutter drive` writes. The two agree, but this one also
/// works without a driver, and gives the percentiles the report tabulates.
class FrameRecorder {
  final _timings = <FrameTiming>[];
  bool _on = false;

  void _add(List<FrameTiming> t) {
    if (_on) _timings.addAll(t);
  }

  void start() {
    _timings.clear();
    _on = true;
    SchedulerBinding.instance.addTimingsCallback(_add);
  }

  /// Stops recording and summarises. The engine reports timings in batches
  /// (every 100 ms in profile builds), hence the wait before reading them.
  Future<Map<String, Object>> stop() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _on = false;
    SchedulerBinding.instance.removeTimingsCallback(_add);
    return summarise(_timings);
  }

  static Map<String, Object> summarise(List<FrameTiming> timings) {
    if (timings.isEmpty) return {'frames': 0};
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = [for (final t in timings) ms(t.buildDuration)]..sort();
    final raster = [for (final t in timings) ms(t.rasterDuration)]..sort();
    // What a user sees: a frame that took longer than one 60 Hz interval to
    // build or to rasterise is a frame that was late to the screen.
    const budget = 1000 / 60;
    final jank = timings
        .where((t) =>
            ms(t.buildDuration) > budget || ms(t.rasterDuration) > budget)
        .length;
    double pct(List<double> sorted, double q) =>
        _round(sorted[math.min(sorted.length - 1, (sorted.length * q).floor())]);
    double mean(List<double> v) =>
        _round(v.reduce((a, b) => a + b) / v.length);
    return {
      'frames': timings.length,
      'jank_frames': jank,
      'build_ms_mean': mean(build),
      'build_ms_p50': pct(build, 0.5),
      'build_ms_p90': pct(build, 0.9),
      'build_ms_p99': pct(build, 0.99),
      'build_ms_max': _round(build.last),
      'raster_ms_mean': mean(raster),
      'raster_ms_p90': pct(raster, 0.9),
      'raster_ms_p99': pct(raster, 0.99),
      'raster_ms_max': _round(raster.last),
    };
  }
}

/// Samples the image cache while a scenario runs and keeps the peak — the
/// cache shrinks back as it evicts, so the value at the end understates what
/// scrolling cost.
class ImageCacheSampler {
  double _peakMb = 0;
  int _peakLive = 0;
  bool _on = false;

  void start() {
    _peakMb = 0;
    _peakLive = 0;
    _on = true;
    _tick();
  }

  void _tick() {
    if (!_on) return;
    final cache = PaintingBinding.instance.imageCache;
    _peakMb = math.max(_peakMb, cache.currentSizeBytes / (1 << 20));
    _peakLive = math.max(_peakLive, cache.liveImageCount);
    Future<void>.delayed(const Duration(milliseconds: 50), _tick);
  }

  Map<String, Object> stop() {
    _on = false;
    return {
      'image_cache_peak_mb': _round(_peakMb),
      'live_images_peak': _peakLive,
    };
  }
}
