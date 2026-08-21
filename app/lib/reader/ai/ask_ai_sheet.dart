import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/page_insets.dart';
import 'ai_client.dart';
import 'ai_settings.dart';
import 'ai_setup_sheet.dart';

/// Asking a model about what you are reading (request 8/19 #10).
///
/// The passage is shown first and the question second, in that order on
/// purpose: this sheet sends text off the device, and the text it is about to
/// send should be the first thing on screen. The header says where it goes.
class AskAiSheet extends StatefulWidget {
  const AskAiSheet({
    super.key,
    required this.passage,
    required this.settings,
    this.bookTitle,
    this.what = 'passage',
    this.client,
    this.onSaveAsNote,
  });

  final String passage;
  final AiSettings settings;
  final String? bookTitle;

  /// What the text is, for the sentence describing it: a passage, a page, a
  /// chapter.
  final String what;

  /// Passed in by tests, which have no model to ask.
  final AiClient? client;

  final Future<void> Function(String answer)? onSaveAsNote;

  @override
  State<AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<AskAiSheet> {
  final _question = TextEditingController();
  String? _answer;
  String? _error;
  bool _busy = false;
  bool _saved = false;

  /// The questions worth a button. Everything else is typed — these are the
  /// three anyone asks of a paragraph they did not follow.
  static const _presets = [
    'Explain this in plain language.',
    'Summarise it in a sentence.',
    'What is the context here?',
  ];

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
      _saved = false;
    });
    final client = widget.client ??
        AiClient(
          baseUrl: widget.settings.baseUrl,
          model: widget.settings.model,
          apiKey: widget.settings.apiKey,
        );
    try {
      final answer = await client.ask(
        passage: widget.passage,
        question: question.trim(),
        bookTitle: widget.bookTitle,
      );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _busy = false;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } finally {
      // Only ours to close; a client passed in belongs to the caller.
      if (widget.client == null) client.close();
    }
  }

  Future<void> _configure() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AiSetupSheet(settings: widget.settings),
    );
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final answer = _answer;
    final save = widget.onSaveAsNote;
    if (answer == null || save == null) return;
    await save(answer);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settings;
    final trimmed = trimPassage(widget.passage);
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
                child: Text('Ask a model', style: theme.textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Where the model is',
                onPressed: _configure,
              ),
            ],
          ),
          if (settings.isConfigured) ...[
            const SizedBox(height: 2),
            Text(
              settings.isLocal
                  ? 'This ${widget.what} goes to ${settings.model} on this '
                      'machine.'
                  : 'This ${widget.what} will be sent to ${settings.host}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: settings.isLocal
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // What is about to be sent, before anything is sent.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                trimmed,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          if (trimmed.length < widget.passage.length) ...[
            const SizedBox(height: 4),
            Text(
              'Only the first ${maxPassageCharacters ~/ 1000}k characters are '
              'sent.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          if (!settings.isConfigured)
            _NotSetUp(onConfigure: _configure)
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  ActionChip(
                    label: Text(preset.replaceFirst(RegExp(r'[.?]$'), '')),
                    onPressed: _busy ? null : () => _ask(preset),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _question,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: _busy ? null : _ask,
              decoration: InputDecoration(
                hintText: 'Or ask something else',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Ask',
                  onPressed: _busy ? null : () => _ask(_question.text),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!)),
                ],
              )
            else if (_answer != null) ...[
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(_answer!),
                ),
              ),
              const SizedBox(height: 4),
              // Said once, under every answer: these things are confidently
              // wrong sometimes, and the book on screen is the authority.
              Text(
                'A model can be wrong. The book is the one that knows.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _answer!));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied')),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy'),
                  ),
                  if (widget.onSaveAsNote != null)
                    TextButton.icon(
                      onPressed: _saved ? null : _save,
                      icon: Icon(
                          _saved ? Icons.check : Icons.sticky_note_2_outlined),
                      label: Text(_saved ? 'Saved as a note' : 'Save as a note'),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _NotSetUp extends StatelessWidget {
  const _NotSetUp({required this.onConfigure});

  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No model named yet. Any server speaking the OpenAI chat API will '
          'do — one running on this machine, or a paid one.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onConfigure,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Name a model'),
        ),
      ],
    );
  }
}
