// Summarises and compares profiling runs (tool/perf_run.sh,
// docs/PERFORMANCE.md). Plain Dart — no Flutter — so it runs with the SDK's
// `dart` straight from the shell script:
//
//   dart tool/perf_report.dart summarize <run dir>
//   dart tool/perf_report.dart diff <run dir A> <run dir B>
//
// `summarize` reads what a run left behind (gui/metrics.json,
// gui/timeline_summaries.json, startup.jsonl) and writes:
//
//   summary.json  one flat map, "scenario.metric" -> number, plus the run's
//                 metadata — the thing `diff` compares
//   summary.md    the same as tables, for reading
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length == 2 && args[0] == 'summarize') {
    final md = summarize(Directory(args[1]));
    stdout.write(md);
  } else if (args.length == 3 && args[0] == 'diff') {
    stdout.write(diff(Directory(args[1]), Directory(args[2])));
  } else {
    stderr.writeln('usage: perf_report.dart summarize <run> | diff <a> <b>');
    exitCode = 64;
  }
}

Map<String, dynamic>? _json(File f) => f.existsSync()
    ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
    : null;

/// The GUI scenarios in the order the report lists them, and the columns.
const _scenarioColumns = [
  'shown_ms',
  'settled_ms',
  'wall_ms',
  'frames',
  'jank_frames',
  'build_ms_p50',
  'build_ms_p90',
  'build_ms_p99',
  'build_ms_max',
  'raster_ms_p90',
  'raster_ms_p99',
  'raster_ms_max',
  'image_cache_peak_mb',
  'image_cache_mb',
  'rss_mb',
];

/// Recorded, kept in summary.json, but too routine to list under Details.
const _quiet = {
  'build_ms_mean',
  'raster_ms_mean',
  'image_cache_entries',
  'live_images',
  'live_images_peak',
  'distance_px',
  'extent_px',
};

/// From Flutter's `TimelineSummary`, kept alongside our own frame numbers: the
/// two should agree, and when they do not, the timeline is the one to open.
const _timelineKeys = {
  '90th_percentile_frame_build_time_millis': 'tl_build_p90',
  '99th_percentile_frame_build_time_millis': 'tl_build_p99',
  'worst_frame_build_time_millis': 'tl_build_max',
  'missed_frame_build_budget_count': 'tl_build_missed',
  '90th_percentile_frame_rasterizer_time_millis': 'tl_raster_p90',
  '99th_percentile_frame_rasterizer_time_millis': 'tl_raster_p99',
  'missed_frame_rasterizer_budget_count': 'tl_raster_missed',
  'new_gen_gc_count': 'tl_gc_new',
  'old_gen_gc_count': 'tl_gc_old',
};

String summarize(Directory run) {
  final flat = <String, num>{};
  final meta = _json(File('${run.path}/meta.json')) ?? {};
  final seed = _json(File('${run.path}/seed.json'));
  final metrics = _json(File('${run.path}/gui/metrics.json')) ?? {};
  final timelines =
      _json(File('${run.path}/gui/timeline_summaries.json')) ?? {};

  final scenarios = <String>[];
  for (final e in metrics.entries) {
    final v = e.value;
    if (v is Map<String, dynamic>) {
      if (e.key == 'library') continue;
      scenarios.add(e.key);
      for (final m in v.entries) {
        if (m.value is num) flat['${e.key}.${m.key}'] = m.value as num;
      }
    } else if (v is num) {
      flat[e.key] = v;
    }
  }
  for (final e in timelines.entries) {
    final v = e.value;
    if (v is! Map<String, dynamic>) continue;
    for (final k in _timelineKeys.entries) {
      final n = v[k.key];
      if (n is num) flat['${e.key}.${k.value}'] = n;
    }
  }

  // Cold starts: the median of the counted launches, with the spread.
  final starts = <Map<String, dynamic>>[
    for (final line
        in File('${run.path}/startup.jsonl').existsSync()
            ? File('${run.path}/startup.jsonl').readAsLinesSync()
            : const <String>[])
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  final startKeys = <String>{
    for (final s in starts)
      for (final e in s.entries)
        if (e.value is num) e.key,
  };
  final startStats = <String, ({num median, num min, num max})>{};
  for (final k in startKeys) {
    final values = [
      for (final s in starts)
        if (s[k] is num) s[k] as num,
    ]..sort();
    if (values.isEmpty) continue;
    final stat = (
      median: values[values.length ~/ 2],
      min: values.first,
      max: values.last,
    );
    startStats[k] = stat;
    flat['cold_start.$k'] = stat.median;
  }

  File('${run.path}/summary.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'meta': meta,
      'seed': ?seed,
      if (metrics['library'] != null) 'library': metrics['library'],
      'metrics': flat,
    }),
  );

  final md = StringBuffer()
    ..writeln(
      '# Profiling run ${run.uri.pathSegments.where((s) => s.isNotEmpty).last}',
    )
    ..writeln()
    ..writeln(
      '${meta['target'] ?? ''} · commit ${meta['commit'] ?? '?'} · '
      '${meta['date'] ?? ''} · load ${meta['load'] ?? '?'} · '
      'window ${metrics['window'] ?? '?'}',
    )
    ..writeln();
  if (metrics['library'] != null) {
    md.writeln(
      'Library: ${(metrics['library'] as Map).entries.map((e) => '${e.key} ${e.value}').join(', ')}',
    );
    md.writeln();
  }
  if (startStats.isNotEmpty) {
    md
      ..writeln('## Cold start (${starts.length} launches, median [min–max])')
      ..writeln()
      ..writeln('| | |')
      ..writeln('|---|---|');
    for (final e in startStats.entries) {
      md.writeln(
        '| ${e.key} | ${e.value.median} [${e.value.min}–${e.value.max}] |',
      );
    }
    md.writeln();
  }
  if (scenarios.isNotEmpty) {
    final cols = [
      for (final c in _scenarioColumns)
        if (scenarios.any((s) => flat.containsKey('$s.$c'))) c,
    ];
    md
      ..writeln('## Scenarios')
      ..writeln()
      ..writeln('| scenario | ${cols.join(' | ')} |')
      ..writeln('|---|${cols.map((_) => '---:').join('|')}|');
    final starved = <String>[];
    for (final s in scenarios) {
      // A scenario that ran for seconds but drew a fraction of the frames its
      // length allows, *without* those frames being slow, was not slow: the
      // compositor stopped asking for frames (a sleeping monitor, a locked
      // screen, a hidden window). Slow frames explain few frames; fast ones
      // do not.
      final wall = flat['$s.wall_ms'];
      final frames = flat['$s.frames'];
      final work =
          (flat['$s.build_ms_p90'] ?? 0) + (flat['$s.raster_ms_p90'] ?? 0);
      if (wall != null &&
          frames != null &&
          frames > 0 &&
          wall > 2000 &&
          frames < wall / 16.7 * 0.4 &&
          work < wall / frames / 2) {
        starved.add(s);
      }
      md.writeln(
        '| $s${starved.contains(s) ? ' (starved)' : ''} | '
        '${cols.map((c) => flat['$s.$c'] ?? '').join(' | ')} |',
      );
    }
    md.writeln();
    if (starved.isNotEmpty) {
      md
        ..writeln(
          '**Starved of frames — not valid:** ${starved.join(', ')}. '
          'Was the display asleep or locked? Rerun with it awake, or with '
          '--headless.',
        )
        ..writeln();
    }
    final extras = [
      for (final s in scenarios)
        for (final e in (metrics[s] as Map<String, dynamic>).entries)
          if (!_scenarioColumns.contains(e.key) && !_quiet.contains(e.key))
            '- $s.${e.key}: ${jsonEncode(e.value)}',
      for (final e in flat.entries)
        if (!e.key.contains('.')) '- ${e.key}: ${e.value}',
    ];
    if (extras.isNotEmpty) {
      md
        ..writeln('Details:')
        ..writeln()
        ..writeAll(extras, '\n')
        ..writeln()
        ..writeln();
    }
  }
  File('${run.path}/summary.md').writeAsStringSync(md.toString());
  return md.toString();
}

String diff(Directory a, Directory b) {
  Map<String, num> load(Directory d) {
    final s = _json(File('${d.path}/summary.json'));
    if (s == null) throw StateError('no summary.json in ${d.path}');
    return (s['metrics'] as Map<String, dynamic>).cast<String, num>();
  }

  final ma = load(a);
  final mb = load(b);
  final keys = {...ma.keys, ...mb.keys}.toList()..sort();
  final out = StringBuffer()
    ..writeln(
      '| metric | ${a.uri.pathSegments.where((s) => s.isNotEmpty).last} '
      '| ${b.uri.pathSegments.where((s) => s.isNotEmpty).last} | change |',
    )
    ..writeln('|---|---:|---:|---:|');
  for (final k in keys) {
    final x = ma[k];
    final y = mb[k];
    final change = (x == null || y == null || x == 0)
        ? ''
        : '${y >= x ? '+' : ''}${((y - x) / x * 100).toStringAsFixed(0)}%';
    out.writeln('| $k | ${x ?? ''} | ${y ?? ''} | $change |');
  }
  return out.toString();
}
