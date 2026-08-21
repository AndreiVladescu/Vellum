/// What a finger asked for, once the wobble is taken out of it.
///
/// Kept apart from the reader itself because these are arithmetic, and
/// arithmetic is worth testing: "did that count as a swipe" and "has this drag
/// committed to being vertical" are the two questions behind every reported
/// gesture bug, and neither of them needs a PDF to answer.
library;

import 'dart:ui';

/// A page turn asked for by a swipe.
enum SwipeTurn {
  /// Up or left — the direction text leaves the screen as you read on.
  forward,

  /// Down or right.
  back,
}

/// How far a pointer must travel to mean it.
const swipeDistance = 64.0;

/// And how quickly. A drag that took two seconds is someone repositioning the
/// page, not flicking it over.
const swipeWindow = Duration(milliseconds: 500);

/// The turn a completed drag asked for, or null if it asked for nothing.
///
/// [atRestingZoom] is the gate that keeps a zoomed page readable: once you have
/// zoomed in, dragging is how you look around, and taking that over to turn
/// pages would leave no way to see the rest of the page.
SwipeTurn? swipeTurn({
  required Offset delta,
  required Duration elapsed,
  required bool paged,
  required bool atRestingZoom,
}) {
  if (!paged || !atRestingZoom) return null;
  if (elapsed > swipeWindow) return null;
  // Whichever axis moved further is the one meant, so swiping up and swiping
  // left do the same thing — which is what was asked for, and what saves
  // anyone from having to remember which one this reader wanted.
  final vertical = delta.dy.abs() > delta.dx.abs();
  final travel = vertical ? delta.dy : delta.dx;
  if (travel.abs() < swipeDistance) return null;
  return travel < 0 ? SwipeTurn.forward : SwipeTurn.back;
}

/// Below this, a drag has not committed to a direction — every drag looks
/// diagonal in its first few pixels.
const axisDecisionDistance = 16.0;

/// Whether a drag has travelled far enough to be judged at all.
bool axisDecided(Offset delta) => delta.distance >= axisDecisionDistance;

/// Whether this drag is a vertical one, and so should hold its horizontal
/// position while it runs.
///
/// Two to one rather than merely "more down than across": a hand dragging down
/// a phone drifts, and a rule that locked on the slightest vertical bias would
/// make deliberate diagonal panning impossible.
bool isVerticalDrag(Offset delta) => delta.dy.abs() > delta.dx.abs() * 2;
