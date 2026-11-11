import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../local_engine_backend.dart';
import 'on_device_backend.dart';
import '../translation_backend.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../l10n/labels.dart';

/// The languages kept on this device, and the switch for each.
///
/// A pack is downloaded once — roughly 30 MB — and then translation happens
/// here, on a train, in a basement, with the passage never leaving the machine.
/// That is the whole reason this screen exists rather than a server address.
class LanguagePacksSheet extends StatefulWidget {
  const LanguagePacksSheet({super.key, this.packs});

  /// Injectable so a test can drive the list without a phone attached.
  final LanguagePacks? packs;

  @override
  State<LanguagePacksSheet> createState() => _LanguagePacksSheetState();
}

class _LanguagePacksSheetState extends State<LanguagePacksSheet> {
  late final LanguagePacks _packs = widget.packs ?? LanguagePacks();

  Map<TranslationLanguage, bool> _installed = const {};
  bool _loading = true;

  /// The language a download or removal is in flight for, so only its own row
  /// shows a spinner — the rest of the list stays usable.
  TranslationLanguage? _working;

  /// Off means "download over mobile data too". On by default: a pack is tens
  /// of megabytes, and nobody means to spend an allowance by pressing a button
  /// inside a book.
  bool _wifiOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await _packs.installedState();
    if (!mounted) return;
    setState(() {
      _installed = state;
      _loading = false;
    });
  }

  Future<void> _toggle(TranslationLanguage language, bool install) async {
    setState(() => _working = language);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    try {
      if (install) {
        await _packs.install(language, wifiOnly: _wifiOnly);
      } else {
        await _packs.remove(language);
      }
      if (!mounted) return;
      setState(() => _installed = {..._installed, language: install});
    } on TranslationException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.messageOf(l10n))));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A desktop has no packs to toggle: it has an engine, or it does not. Say
    // which, and say exactly what to type — a half-remembered instruction is
    // worse than none.
    if (!OnDeviceBackend.available) return const _LocalEngineHelp();

    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final here = _installed.values.where((v) => v).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translateLanguages, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            l10n.translatePacksBody,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l10n.translatePacksWifiOnly),
            value: _wifiOnly,
            onChanged: (v) => setState(() => _wifiOnly = v),
          ),
          const Divider(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in _installed.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.key.nameOf(l10n)),
                      subtitle: Text(entry.value
                          ? l10n.translatePackOnDevice
                          : l10n.translatePackNotDownloaded),
                      trailing: _working == entry.key
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: entry.value
                                  ? l10n.translatePackRemoveTooltip(
                                      entry.key.nameOf(l10n))
                                  : l10n.translatePackDownloadTooltip(
                                      entry.key.nameOf(l10n)),
                              icon: Icon(entry.value
                                  ? Icons.delete_outline
                                  : Icons.download_outlined),
                              onPressed: _working != null
                                  ? null
                                  : () => _toggle(entry.key, !entry.value),
                            ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            here == 0
                ? l10n.translatePacksNone
                : l10n.translatePacksCount(here),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}


/// What a desktop sees under *Languages*: whether a translator is installed on
/// this machine, and how to get one if not.
///
/// No server appears here on purpose. A passage you are reading should not have
/// to travel to be translated, so the only options offered are ones that run on
/// the machine you are reading on.
class _LocalEngineHelp extends StatefulWidget {
  const _LocalEngineHelp();

  @override
  State<_LocalEngineHelp> createState() => _LocalEngineHelpState();
}

class _LocalEngineHelpState extends State<_LocalEngineHelp> {
  List<LocalEngineBackend> _found = const [];
  Map<LocalEngine, List<String>> _pairs = const {};
  bool _looking = true;

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    setState(() => _looking = true);
    final found = await LocalEngineBackend.detectAll();
    final pairs = <LocalEngine, List<String>>{};
    for (final engine in found) {
      pairs[engine.engine] = await engine.installedPairs();
    }
    if (!mounted) return;
    setState(() {
      _found = found;
      _pairs = pairs;
      _looking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translateLanguages, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            l10n.translateLocalBody,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (_looking)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_found.isNotEmpty) ...[
            // Every engine, with the pairs it actually has. An engine arrives
            // long before its packs do, and two engines rarely cover the same
            // languages — which is why a translation tries each of them.
            for (final backend in _found) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_circle_outline,
                    color: theme.colorScheme.primary),
                title: Text(backend.engine.label),
                subtitle: Text(
                  (_pairs[backend.engine] ?? const []).isEmpty
                      ? l10n.translateInstalledNoPairs
                      : l10n.translateInstalledRuns,
                ),
              ),
              if ((_pairs[backend.engine] ?? const []).isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SelectableText(
                    backend.engine.installHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final pair in _pairs[backend.engine]!)
                        Chip(
                          label: Text(pair),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
            ],
          ]
          else ...[
            Text(
              l10n.translateNothingFound,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final engine in LocalEngine.values)
              _InstallCard(engine: engine),
            const SizedBox(height: 4),
            Text(
              l10n.translateArgosNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: _looking ? null : _look,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.translateLookAgain),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.translateDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstallCard extends StatelessWidget {
  const _InstallCard({required this.engine});

  final LocalEngine engine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(engine.label, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SelectableText(
              engine.installHint,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: engine.installHint));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(L10n.of(context).translateCommandCopied)),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(L10n.of(context).readerCopy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
