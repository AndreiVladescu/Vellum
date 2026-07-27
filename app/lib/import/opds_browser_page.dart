import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'catalog_entry.dart';
import 'opds_client.dart';

/// Browse an OPDS catalogue and pick books to import (plan 5 #21c).
///
/// Pops with the selected entries, each already downloaded to a temporary
/// file, so the caller can hand them straight to the same review wizard every
/// other import source uses. Downloading here rather than during the import is
/// what lets the dry run hash the files and tell you honestly which of them you
/// already have.
class OpdsBrowserPage extends StatefulWidget {
  const OpdsBrowserPage({super.key, this.client, this.initialUrl});

  /// Injectable for tests; a real client is created otherwise.
  final OpdsClient? client;
  final String? initialUrl;

  @override
  State<OpdsBrowserPage> createState() => _OpdsBrowserPageState();
}

class _OpdsBrowserPageState extends State<OpdsBrowserPage> {
  late final OpdsClient _client = widget.client ?? OpdsClient();
  late final TextEditingController _url =
      TextEditingController(text: widget.initialUrl ?? '');

  /// Where we've been, so Back walks up the catalogue rather than leaving it.
  final _history = <Uri>[];
  OpdsFeed? _feed;
  final _selected = <String, OpdsEntry>{};
  bool _busy = false;
  String? _error;
  String _downloadLabel = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUrl;
    if (initial != null && initial.trim().isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _open(initial, push: true));
    }
  }

  @override
  void dispose() {
    _url.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _open(String raw, {bool push = true}) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    // A bare host is what people paste; assume https rather than failing.
    final uri = Uri.tryParse(
      text.startsWith('http://') || text.startsWith('https://')
          ? text
          : 'https://$text',
    );
    if (uri == null) {
      setState(() => _error = 'That does not look like a URL.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final feed = await _client.fetch(uri);
      if (!mounted) return;
      setState(() {
        if (push) _history.add(uri);
        _feed = feed;
        _busy = false;
      });
    } on OpdsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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

  Future<void> _back() async {
    if (_history.length < 2) return;
    _history.removeLast();
    await _open(_history.removeLast().toString());
  }

  /// Downloads each selected entry and pops with the import rows.
  ///
  /// A failed download drops that one row and keeps the rest: a catalogue with
  /// one dead link should still import the other nineteen books.
  Future<void> _importSelected() async {
    if (_selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final workspace =
        await Directory.systemTemp.createTemp('vellum_opds_download');
    final entries = <CatalogEntry>[];
    final failed = <String>[];
    var done = 0;
    for (final entry in _selected.values) {
      if (!mounted) return;
      setState(() {
        _downloadLabel = '${++done} of ${_selected.length}: ${entry.title}';
      });
      final link = entry.acquisitions.first;
      try {
        final bytes = await _client.download(Uri.parse(link.href));
        final safe = entry.title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_');
        final file = File(p.join(workspace.path, '$safe.${link.format}'));
        await file.writeAsBytes(bytes);
        entries.add(entry.toCatalogEntry().copyWith(filePath: file.path));
      } catch (_) {
        failed.add(entry.title);
      }
    }
    if (!mounted) return;
    if (entries.isEmpty) {
      setState(() {
        _busy = false;
        _downloadLabel = '';
        _error = 'Nothing could be downloaded from that catalogue.';
      });
      return;
    }
    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${failed.length} book${failed.length == 1 ? '' : 's'} '
            'could not be downloaded and were skipped'),
      ));
    }
    Navigator.of(context).pop(entries);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feed = _feed;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPDS catalogue'),
        leading: _history.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Up a level',
                onPressed: _busy ? null : _back,
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _url,
                    decoration: const InputDecoration(
                      labelText: 'Catalogue URL',
                      hintText: 'https://example.com/opds',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) => _open(v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _open(_url.text),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!)),
                ],
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_busy && _downloadLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Downloading $_downloadLabel'),
            ),
          Expanded(
            child: feed == null
                ? const _OpdsIntro()
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(feed.title,
                            style: theme.textTheme.titleMedium),
                      ),
                      for (final folder in feed.folders)
                        ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.title),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy || folder.navigationHref == null
                              ? null
                              : () => _open(folder.navigationHref!),
                        ),
                      for (final book in feed.books)
                        CheckboxListTile(
                          value: _selected.containsKey(book.id),
                          onChanged: _busy
                              ? null
                              : (on) => setState(() {
                                    if (on ?? false) {
                                      _selected[book.id] = book;
                                    } else {
                                      _selected.remove(book.id);
                                    }
                                  }),
                          title: Text(book.title),
                          subtitle: Text([
                            if (book.authors.isNotEmpty) book.authors.join(', '),
                            ...[
                              for (final a in book.acquisitions)
                                a.format!.toUpperCase(),
                            ],
                          ].join(' · ')),
                        ),
                      if (feed.nextHref != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton.icon(
                            onPressed:
                                _busy ? null : () => _open(feed.nextHref!),
                            icon: const Icon(Icons.expand_more),
                            label: const Text('Next page'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _busy ? null : _importSelected,
                icon: const Icon(Icons.download),
                label: Text('Review ${_selected.length} book'
                    '${_selected.length == 1 ? '' : 's'}'),
              ),
            ),
    );
  }
}

class _OpdsIntro extends StatelessWidget {
  const _OpdsIntro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rss_feed,
              size: 56,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text('Browse an OPDS catalogue',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Paste the address of any OPDS server — Calibre-Web, Kavita, '
              'Standard Ebooks, or another Vellum. Pick the books you want and '
              'they go through the same review as any other import.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
