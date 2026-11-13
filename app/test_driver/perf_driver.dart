// The host side of the profiling run's GUI half (docs/PERFORMANCE.md). Runs in
// the `flutter drive` process, not in the app: it receives what
// `integration_test/perf_test.dart` reported and writes it to `$PERF_OUT`
// (default `build/perf`).
//
//   metrics.json             the test's own numbers, per scenario
//   timeline_summaries.json  Flutter's `TimelineSummary` per scenario
//   <scenario>.timeline.json the raw timeline, with PERF_KEEP_TIMELINES=1 —
//                            open it in Perfetto (ui.perfetto.dev)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      timeout: const Duration(minutes: 30),
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        final out = Directory(Platform.environment['PERF_OUT'] ?? 'build/perf')
          ..createSync(recursive: true);
        if (data == null) return;
        final keep = Platform.environment['PERF_KEEP_TIMELINES'] == '1';
        final summaries = <String, Object?>{};
        for (final entry in data.entries) {
          if (entry.key == 'metrics') {
            File('${out.path}/metrics.json').writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert(entry.value),
            );
            continue;
          }
          try {
            final timeline = Timeline.fromJson(
              (entry.value as Map).cast<String, dynamic>(),
            );
            final summary = TimelineSummary.summarize(timeline);
            summaries[entry.key] = summary.summaryJson;
            if (keep) {
              await summary.writeTimelineToFile(
                entry.key,
                destinationDirectory: out.path,
                pretty: false,
                includeSummary: false,
              );
            }
          } catch (e) {
            // A scenario too short to hold a frame has nothing to summarise;
            // say so in the file rather than lose the others.
            summaries[entry.key] = {'error': '$e'};
          }
        }
        File('${out.path}/timeline_summaries.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(summaries),
        );
      },
    );
