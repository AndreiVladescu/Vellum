import 'package:flutter/material.dart';

import 'dictionary/dictionary_tile.dart';
import 'page_metric.dart';
import 'reader_settings.dart';
import '../widgets/page_insets.dart';
import 'translate/on_device.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/labels.dart';

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
    final l10n = L10n.of(context);
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
                _Label(l10n.readerSettingsPageColour),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final theme in ReaderTheme.choices)
                      ChoiceChip(
                        label: Text(theme.labelOf(l10n)),
                        selected: !settings.nightMode && settings.theme == theme,
                        // Greyed out while night mode is on, rather than
                        // hidden: it should be obvious *why* the page is black
                        // and which switch to flick to change it.
                        onSelected:
                            settings.nightMode ? null : (_) => settings.setTheme(theme),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.readerSettingsNightMode),
                  subtitle: Text(l10n.readerSettingsNightModeSub),
                  value: settings.nightMode,
                  onChanged: settings.setNightMode,
                ),
                if (showTypography) ...[
                  const SizedBox(height: 16),
                  _Label(l10n.readerSettingsTypeface),
                  SegmentedButton<ReaderFont>(
                    segments: [
                      for (final font in ReaderFont.values)
                        ButtonSegment(value: font, label: Text(font.labelOf(l10n))),
                    ],
                    selected: {settings.font},
                    onSelectionChanged: (s) => settings.setFont(s.first),
                  ),
                  const SizedBox(height: 8),
                  _Slider(
                    label: l10n.readerSettingsTextSize,
                    value: settings.fontSize,
                    min: ReaderSettings.minFontSize,
                    max: ReaderSettings.maxFontSize,
                    display: '${settings.fontSize.round()}',
                    onChanged: settings.setFontSize,
                  ),
                  _Slider(
                    label: l10n.readerSettingsLineSpacing,
                    value: settings.lineHeight,
                    min: ReaderSettings.minLineHeight,
                    max: ReaderSettings.maxLineHeight,
                    display: settings.lineHeight.toStringAsFixed(2),
                    onChanged: settings.setLineHeight,
                  ),
                  _Slider(
                    label: l10n.readerSettingsLineLength,
                    value: settings.measure,
                    min: ReaderSettings.minMeasure,
                    max: ReaderSettings.maxMeasure,
                    display: '${settings.measure.round()}',
                    onChanged: settings.setMeasure,
                  ),
                ],
                if (showPdfOptions) ...[
                  const SizedBox(height: 16),
                  _Label(l10n.readerSettingsMoving),
                  SegmentedButton<PdfPageMode>(
                    segments: [
                      for (final mode in PdfPageMode.values)
                        ButtonSegment(
                            value: mode, label: Text(mode.labelOf(l10n))),
                    ],
                    selected: {settings.pdfMode},
                    onSelectionChanged: (s) => settings.setPdfMode(s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      settings.pdfMode.descriptionOf(l10n),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _Label(l10n.readerSettingsPageFit),
                  SegmentedButton<PdfFit>(
                    segments: [
                      for (final fit in PdfFit.values)
                        ButtonSegment(value: fit, label: Text(fit.labelOf(l10n))),
                    ],
                    selected: {settings.pdfFit},
                    onSelectionChanged: (s) => settings.setPdfFit(s.first),
                  ),
                ],
                _Label(l10n.readerSettingsCounter),
                // The same list the long-press cycles. Both exist because the
                // gesture is quick once you know it and invisible until you do.
                DropdownButtonFormField<PageMetric>(
                  initialValue: settings.pageMetric,
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    helperText: l10n.readerSettingsCounterHelper,
                  ),
                  items: [
                    for (final metric in PageMetric.values)
                      DropdownMenuItem(
                          value: metric, child: Text(metric.labelOf(l10n))),
                  ],
                  onChanged: (metric) {
                    if (metric != null) settings.setPageMetric(metric);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.readerSettingsHideControls),
                  subtitle: Text(l10n.readerSettingsHideControlsSub),
                  value: settings.immersive,
                  onChanged: settings.setImmersive,
                ),
                // Where the word lookup's dictionary is managed. The download
                // is also offered inside the lookup itself, which is where it
                // is first wanted; this is where it can be given back.
                const DictionaryTile(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the translation server is named — the one thing that decides whether
/// the reader has a Translate button at all.
///
/// A field rather than a picker of providers, because there is one backend
/// today and the plan (docs/NEXT_FEATURES.md #12) is to replace it with an
/// engine packed into the app rather than to collect more addresses.
class TranslateServerSheet extends StatefulWidget {
  const TranslateServerSheet({super.key, required this.settings});

  final ReaderSettings settings;

  @override
  State<TranslateServerSheet> createState() => _TranslateServerSheetState();
}

class _TranslateServerSheetState extends State<TranslateServerSheet> {
  late final _url = TextEditingController(text: widget.settings.translateUrl);
  late final _key = TextEditingController(text: widget.settings.translateApiKey);

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: sheetBottomInset(context) + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Only in the full build. The free one has no such translator, so
          // this would be a switch for a thing that isn't there.
          if (onDeviceTranslationAvailable) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.settings.useOnDeviceTranslation,
              onChanged: (v) async {
                await widget.settings.setUseOnDeviceTranslation(v);
                if (context.mounted) setState(() {});
              },
              title: Text(l10n.readerTranslateOnDeviceTitle),
              subtitle: Text(l10n.readerTranslateOnDeviceSub),
            ),
            const Divider(height: 24),
          ],
          Text(l10n.readerTranslateServerTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            l10n.readerTranslateServerBody,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.readerTranslateAddress,
              hintText: 'http://192.168.1.20:5000', // i18n-ignore
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.readerTranslateApiKey,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  await widget.settings.setTranslateServer(url: '', apiKey: '');
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(l10n.readerTranslateTurnOff),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await widget.settings.setTranslateServer(
                    url: _url.text,
                    apiKey: _key.text,
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
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
