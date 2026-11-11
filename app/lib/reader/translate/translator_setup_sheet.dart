import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_engine_backend.dart';
import '../../l10n/gen/app_localizations.dart';



/// What *Languages* shows: whether a translator is installed on this machine,
/// and how to get one if not.
///
/// This used to be two screens in one — a list of ML Kit language packs on a
/// phone, and this on a desktop. ML Kit is gone (a closed Google library, and
/// about 17 MB of proprietary blobs in an otherwise free app), so a translator
/// installed on the machine is the on-device story everywhere, and a
/// LibreTranslate address in the reader's settings is the answer for a phone.
///
/// No server is offered *here* on purpose: a passage you are reading should not
/// have to travel to be translated, so the only thing this screen suggests is
/// something that runs where you are reading.
class TranslatorSetupSheet extends StatefulWidget {
  const TranslatorSetupSheet({super.key});

  @override
  State<TranslatorSetupSheet> createState() => _TranslatorSetupSheetState();
}

class _TranslatorSetupSheetState extends State<TranslatorSetupSheet> {
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
