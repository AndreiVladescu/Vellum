import 'package:flutter/material.dart';

import 'on_device_backend.dart';
import 'translation_backend.dart';

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
    try {
      if (install) {
        await _packs.install(language, wifiOnly: _wifiOnly);
      } else {
        await _packs.remove(language);
      }
      if (!mounted) return;
      setState(() => _installed = {..._installed, language: install});
    } on TranslationException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final here = _installed.values.where((v) => v).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Languages', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Downloaded languages translate on this device — no server, and '
            'nothing leaves the machine. About 30 MB each, kept until you '
            'remove them.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Download over Wi-Fi only'),
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
                      title: Text(entry.key.name),
                      subtitle: Text(entry.value ? 'On this device' : 'Not downloaded'),
                      trailing: _working == entry.key
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: entry.value
                                  ? 'Remove ${entry.key.name}'
                                  : 'Download ${entry.key.name}',
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
                ? 'Nothing downloaded yet — a translation needs the language it '
                    'is coming *from* and the one it is going *to*.'
                : '$here language${here == 1 ? '' : 's'} on this device.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
