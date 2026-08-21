import 'package:flutter/material.dart';

import 'dictionary_store.dart';

/// The dictionary's row in the reader's options: whether it is here, how much
/// room it takes, and the way to get it or give the space back.
///
/// The download also lives inside the lookup sheet, where it is first wanted.
/// This is the other half — nobody would think to look up a word in order to
/// *remove* a dictionary.
class DictionaryTile extends StatefulWidget {
  const DictionaryTile({super.key, this.store});

  /// Passed in by tests; otherwise the app's own.
  final DictionaryStore? store;

  @override
  State<DictionaryTile> createState() => _DictionaryTileState();
}

class _DictionaryTileState extends State<DictionaryTile> {
  DictionaryStore? _store;
  bool _busy = true;
  double? _progress;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    DictionaryStore? store;
    try {
      store = widget.store ?? await DictionaryStore.open();
    } catch (_) {
      // No support directory to look in — a platform without one, or a test
      // harness. The row simply does not appear; nothing else in the sheet
      // should fail because of it.
    }
    if (!mounted) return;
    setState(() {
      _store = store;
      _busy = false;
    });
  }

  Future<void> _download() async {
    final store = _store;
    if (store == null) return;
    setState(() {
      _working = true;
      _progress = 0;
      _error = null;
    });
    try {
      await store.download(onProgress: (fraction) {
        if (mounted) setState(() => _progress = fraction);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is DictionaryInstallException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove() async {
    await _store?.remove();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = _store;
    if (_busy || store == null) return const SizedBox.shrink();
    final installed = store.isInstalled;
    final megabytes = installed
        ? (store.bytesOnDisk / (1 << 20)).round()
        : (wordNetDownloadBytes / (1 << 20)).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Dictionary'),
          subtitle: Text(installed
              ? 'WordNet, on this device · $megabytes MB'
              : 'Not installed · a $megabytes MB download'),
          trailing: _working
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, value: _progress),
                )
              : TextButton(
                  onPressed: installed ? _remove : _download,
                  child: Text(installed ? 'Remove' : 'Download'),
                ),
        ),
        if (_error != null)
          Text(_error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
      ],
    );
  }
}
