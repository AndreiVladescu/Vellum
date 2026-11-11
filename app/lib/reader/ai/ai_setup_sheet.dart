import 'package:flutter/material.dart';

import '../../widgets/page_insets.dart';
import 'ai_settings.dart';
import '../../l10n/gen/app_localizations.dart';

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
    final l10n = L10n.of(context);
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
            Text(l10n.aiAskTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              l10n.aiSetupBody,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.aiAddressLabel,
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: l10n.aiAddressHelper,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: InputDecoration(
                labelText: l10n.aiModelLabel,
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: l10n.aiModelHelper,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: !_showKey,
              decoration: InputDecoration(
                labelText: l10n.aiKeyLabel,
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: l10n.aiKeyHelper,
                suffixIcon: IconButton(
                  icon: Icon(
                      _showKey ? Icons.visibility_off : Icons.visibility),
                  tooltip: _showKey ? l10n.aiKeyHide : l10n.aiKeyShow,
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
            if (widget.settings.keyInsecure) ...[
              const SizedBox(height: 8),
              Text(
                l10n.aiKeyInsecure,
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
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: Text(l10n.save)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
