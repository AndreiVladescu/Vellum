import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/page_insets.dart';
import 'dictionary_store.dart';
import 'wordnet.dart';

/// What a word means, without leaving the book (request 8/19 #9).
///
/// Opens looking the word up, the way [TranslateSheet] opens translating: you
/// asked by pressing the button, and a sheet that then wants a second press is
/// asking twice. If the dictionary is not on the device yet, this is also where
/// it is fetched — one screen for the word and for the thing that answers it,
/// so a first lookup is not a trip through settings.
class DictionarySheet extends StatefulWidget {
  const DictionarySheet({
    super.key,
    required this.word,
    this.store,
    this.onSaveAsNote,
  });

  final String word;

  /// Normally opened from the app's own support directory; passed in by tests,
  /// which have no device to install anything on.
  final DictionaryStore? store;

  /// Keeps the definition with the word it belongs to, as a note on the book.
  final Future<void> Function(String definition)? onSaveAsNote;

  @override
  State<DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<DictionarySheet> {
  DictionaryStore? _store;
  List<WordSense>? _senses;
  String? _error;
  bool _busy = true;

  /// Null while nothing is downloading; 0–1, or null-inside-busy while the work
  /// has no measurable length. See [DictionaryProgress].
  double? _progress;
  bool _downloading = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = widget.store ?? _store ?? await DictionaryStore.open();
      if (!mounted) return;
      _store = store;
      if (!store.isInstalled) {
        setState(() {
          _senses = null;
          _busy = false;
        });
        return;
      }
      final senses = await store.wordNet.lookup(widget.word);
      if (!mounted) return;
      setState(() {
        _senses = senses;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _download() async {
    final store = _store;
    if (store == null) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await store.download(onProgress: (fraction) {
        if (mounted) setState(() => _progress = fraction);
      });
      if (!mounted) return;
      setState(() => _downloading = false);
      await _look();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e is DictionaryInstallException
            ? e.message
            : 'The dictionary could not be downloaded: $e';
      });
    }
  }

  /// The word, its senses and their synonyms, as one block of text — what a
  /// note wants, and what the clipboard wants.
  String get _asText {
    final senses = _senses ?? const <WordSense>[];
    return [
      widget.word,
      for (final sense in senses)
        [
          '(${sense.partOfSpeech}) ${sense.definition}',
          if (sense.synonyms.isNotEmpty) 'also: ${sense.synonyms.join(', ')}',
        ].join('\n'),
    ].join('\n\n');
  }

  Future<void> _save() async {
    final save = widget.onSaveAsNote;
    if (save == null || (_senses?.isEmpty ?? true)) return;
    await save(_asText);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final senses = _senses;
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
          Row(
            children: [
              Expanded(
                child: Text(widget.word, style: theme.textTheme.headlineSmall),
              ),
              if (senses != null && senses.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy_all_outlined),
                  tooltip: 'Copy',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _asText));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied')),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_downloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              _progress == null
                  ? 'Unpacking…'
                  : 'Downloading… ${((_progress ?? 0) * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
          ] else if (_error != null)
            _Message(
              icon: Icons.error_outline,
              colour: theme.colorScheme.error,
              text: _error!,
            )
          else if (senses == null)
            // Not installed. The offer, with what it costs, before it starts.
            _NotInstalled(onDownload: _download)
          else if (senses.isEmpty)
            _Message(
              icon: Icons.search_off,
              colour: theme.colorScheme.onSurfaceVariant,
              text: 'No entry for “${widget.word}”. The dictionary covers '
                  'nouns, verbs, adjectives and adverbs — not names, and not '
                  'words like “the”.',
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: senses.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, i) => _Sense(sense: senses[i]),
              ),
            ),
          if (widget.onSaveAsNote != null &&
              senses != null &&
              senses.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saved ? null : _save,
                icon: Icon(_saved ? Icons.check : Icons.sticky_note_2_outlined),
                label: Text(_saved ? 'Saved as a note' : 'Save as a note'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One meaning: what it is, what it means, and what else says the same thing.
class _Sense extends StatelessWidget {
  const _Sense({required this.sense});

  final WordSense sense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sense.partOfSpeech,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 2),
        Text(sense.definition, style: theme.textTheme.bodyMedium),
        if (sense.synonyms.isNotEmpty) ...[
          const SizedBox(height: 6),
          // The synonyms half of the request, and the reason a thesaurus is not
          // a second feature: a WordNet sense *is* its set of synonyms.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final synonym in sense.synonyms)
                Chip(
                  label: Text(synonym),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
        if (sense.examples.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final example in sense.examples)
            Text(
              '“$example”',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }
}

class _NotInstalled extends StatelessWidget {
  const _NotInstalled({required this.onDownload});

  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final megabytes = (wordNetDownloadBytes / (1 << 20)).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The dictionary is not on this device yet. It is a $megabytes MB '
          'download, and once it is here every lookup happens on the device — '
          'no word you read is ever sent anywhere.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          wordNetLicence,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onDownload,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Download the dictionary'),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.colour,
    required this.text,
  });

  final IconData icon;
  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colour),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
