import 'package:flutter/material.dart';

import '../../widgets/page_insets.dart';
import 'ai_settings.dart';

/// Where the model is named.
///
/// An address, a model name and an optional key — the same three fields
/// whether the model is running on this machine or is somebody's paid service,
/// because the request is identical either way. The examples are there because
/// the commonest failure is a base URL that is nearly right.
class AiSetupSheet extends StatefulWidget {
  const AiSetupSheet({super.key, required this.settings});

  final AiSettings settings;

  @override
  State<AiSetupSheet> createState() => _AiSetupSheetState();
}

class _AiSetupSheetState extends State<AiSetupSheet> {
  late final _url = TextEditingController(text: widget.settings.baseUrl);
  late final _model = TextEditingController(text: widget.settings.model);
  late final _key = TextEditingController(text: widget.settings.apiKey ?? '');
  bool _showKey = false;

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.settings.save(
      baseUrl: _url.text,
      model: _model.text,
      apiKey: _key.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: sheetBottomInset(context) + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ask a model', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Any server that speaks the OpenAI chat API: one you run '
              'yourself, or a paid one. The passage you ask about is sent to '
              'this address, and nowhere else.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Address',
                border: OutlineInputBorder(),
                isDense: true,
                helperText: 'http://localhost:11434 for Ollama · '
                    'https://api.openai.com/v1',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
                isDense: true,
                helperText: 'llama3.2, mistral, gpt-4o-mini — whatever that '
                    'server has',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: !_showKey,
              decoration: InputDecoration(
                labelText: 'Key (optional)',
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: 'A model on your own machine needs none.',
                suffixIcon: IconButton(
                  icon: Icon(
                      _showKey ? Icons.visibility_off : Icons.visibility),
                  tooltip: _showKey ? 'Hide' : 'Show',
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
            if (widget.settings.keyInsecure) ...[
              const SizedBox(height: 8),
              Text(
                'This device has no secure store, so the key is kept in plain '
                'settings.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
