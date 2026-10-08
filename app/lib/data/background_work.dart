import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:pool/pool.dart';

/// How many background isolates run at once: one per spare core, at most four.
///
/// An isolate is Dart's thread — it runs on its own core with its own memory —
/// so CPU-heavy work in one leaves the UI isolate free to draw frames. The UI
/// isolate keeps a core to itself, and past four a phone runs hot for no
/// visible gain.
final int backgroundSlots = (Platform.numberOfProcessors - 1).clamp(1, 4);

/// Shared by everything heavy — cover thumbnails, file hashes — so that
/// together they never take more than [backgroundSlots] cores, rather than
/// each claiming a few of its own.
final _slots = Pool(backgroundSlots);

/// Runs [computation] in a fresh background isolate once a slot is free.
///
/// The closure is copied into the isolate along with everything it captures,
/// so callers hand it plain values (paths, numbers), not objects with a
/// database or a widget behind them. Never call this from inside another
/// [inBackground] computation's wait: a slot waiting on a slot can deadlock.
Future<R> inBackground<R>(FutureOr<R> Function() computation) =>
    _slots.withResource(() => Isolate.run(computation));
