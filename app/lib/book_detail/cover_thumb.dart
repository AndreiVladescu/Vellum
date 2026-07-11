import 'dart:io';

import 'package:flutter/material.dart';

/// The book's cover: shows the image and, on hover (desktop), reveals a
/// "Change cover" overlay. Tapping picks a new image — the same mechanic as the
/// server console. A cover-less book shows a clickable "No cover" placeholder.
class CoverThumb extends StatefulWidget {
  const CoverThumb({super.key, required this.cover, required this.onTap});

  final File? cover;
  final VoidCallback onTap;

  @override
  State<CoverThumb> createState() => CoverThumbState();
}

class CoverThumbState extends State<CoverThumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = widget.cover;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Touch platforms never hover, so the "Change cover" overlay would never
    // appear — show a persistent edit badge instead so it's discoverable.
    final isTouch = theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS ||
        theme.platform == TargetPlatform.fuchsia;
    final placeholder = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text('No cover', style: theme.textTheme.bodySmall),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 110,
            height: 162,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover != null)
                  // Detail view gets a more generous decode budget (2× the
                  // 110px layout width) than the shelf spines.
                  Image.file(
                    cover,
                    fit: BoxFit.cover,
                    cacheWidth: (110 * 2 * dpr).round(),
                    errorBuilder: (_, _, _) => placeholder,
                  )
                else
                  placeholder,
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: const Text(
                      'Change\ncover',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
                if (isTouch)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit,
                          size: 15, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
