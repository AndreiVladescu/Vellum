import 'package:flutter/material.dart';

import 'reader_settings.dart';

/// The reader's appearance controls (plan 5 #23).
///
/// One sheet for both readers, with the format-specific rows shown only where
/// they apply: EPUB typography can restyle reflowable text, while a PDF is a
/// rendered page whose only comfort levers are fit and night mode.
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.settings,
    required this.showTypography,
    required this.showPdfOptions,
  });

  final ReaderSettings settings;

  /// EPUB: font, size, line height, measure.
  final bool showTypography;

  /// PDF: fit and night mode.
  final bool showPdfOptions;

  static Future<void> show(
    BuildContext context, {
    required ReaderSettings settings,
    bool typography = false,
    bool pdf = false,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => ReaderSettingsSheet(
          settings: settings,
          showTypography: typography,
          showPdfOptions: pdf,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Label('Page colour'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final theme in ReaderTheme.values)
                      ChoiceChip(
                        label: Text(theme.label),
                        selected: settings.theme == theme,
                        onSelected: (_) => settings.setTheme(theme),
                        avatar: Container(
                          decoration: BoxDecoration(
                            color: theme.background,
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.foreground),
                          ),
                        ),
                      ),
                  ],
                ),
                if (showTypography) ...[
                  const SizedBox(height: 16),
                  _Label('Typeface'),
                  SegmentedButton<ReaderFont>(
                    segments: [
                      for (final font in ReaderFont.values)
                        ButtonSegment(value: font, label: Text(font.label)),
                    ],
                    selected: {settings.font},
                    onSelectionChanged: (s) => settings.setFont(s.first),
                  ),
                  const SizedBox(height: 8),
                  _Slider(
                    label: 'Text size',
                    value: settings.fontSize,
                    min: ReaderSettings.minFontSize,
                    max: ReaderSettings.maxFontSize,
                    display: '${settings.fontSize.round()}',
                    onChanged: settings.setFontSize,
                  ),
                  _Slider(
                    label: 'Line spacing',
                    value: settings.lineHeight,
                    min: ReaderSettings.minLineHeight,
                    max: ReaderSettings.maxLineHeight,
                    display: settings.lineHeight.toStringAsFixed(2),
                    onChanged: settings.setLineHeight,
                  ),
                  _Slider(
                    label: 'Line length',
                    value: settings.measure,
                    min: ReaderSettings.minMeasure,
                    max: ReaderSettings.maxMeasure,
                    display: '${settings.measure.round()}',
                    onChanged: settings.setMeasure,
                  ),
                ],
                if (showPdfOptions) ...[
                  const SizedBox(height: 16),
                  _Label('Moving through the book'),
                  SegmentedButton<PdfPageMode>(
                    segments: [
                      for (final mode in PdfPageMode.values)
                        ButtonSegment(value: mode, label: Text(mode.label)),
                    ],
                    selected: {settings.pdfMode},
                    onSelectionChanged: (s) => settings.setPdfMode(s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      settings.pdfMode.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _Label('Page fit'),
                  SegmentedButton<PdfFit>(
                    segments: [
                      for (final fit in PdfFit.values)
                        ButtonSegment(value: fit, label: Text(fit.label)),
                    ],
                    selected: {settings.pdfFit},
                    onSelectionChanged: (s) => settings.setPdfFit(s.first),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Night mode'),
                    subtitle: const Text(
                        'Darkens the page without turning photos into negatives'),
                    value: settings.pdfNightMode,
                    onChanged: settings.setPdfNightMode,
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hide controls while reading'),
                  subtitle: const Text('Tap the page to bring them back'),
                  value: settings.immersive,
                  onChanged: settings.setImmersive,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 44, child: Text(display, textAlign: TextAlign.end)),
      ],
    );
  }
}
