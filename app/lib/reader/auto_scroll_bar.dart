import 'package:flutter/material.dart';

import 'auto_scroll.dart';

/// The floating speed control for the self-scroller, shared by both readers.
///
/// Slower, faster, stop — three targets big enough to hit without looking,
/// which is the state you are in while it is running. It stays on screen in
/// reading mode, where the rest of the chrome is gone: this is the one control
/// still needed once the page is moving on its own.
class AutoScrollBar extends StatelessWidget {
  const AutoScrollBar({
    super.key,
    required this.speed,
    required this.unit,
    required this.min,
    required this.max,
    required this.onSpeed,
    required this.onStop,
  });

  final double speed;

  /// What one unit of speed is here: 'pages' in a PDF, 'lines' in an EPUB.
  final String unit;

  final double min;
  final double max;

  final void Function(double speed) onSpeed;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface.withValues(alpha: 0.85),
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              color: scheme.onInverseSurface,
              tooltip: 'Slower',
              onPressed: speed <= min
                  ? null
                  : () => onSpeed(
                      stepAutoScrollSpeed(
                        speed,
                        faster: false,
                        min: min,
                        max: max,
                      ),
                    ),
            ),
            Text(
              autoScrollSpeedLabel(speed, unit),
              style: TextStyle(color: scheme.onInverseSurface),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              color: scheme.onInverseSurface,
              tooltip: 'Faster',
              onPressed: speed >= max
                  ? null
                  : () => onSpeed(
                      stepAutoScrollSpeed(
                        speed,
                        faster: true,
                        min: min,
                        max: max,
                      ),
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              color: scheme.onInverseSurface,
              tooltip: 'Stop scrolling by itself',
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}
