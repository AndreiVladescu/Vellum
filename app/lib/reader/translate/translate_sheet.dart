import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../reader_settings.dart';
import 'local_engine_backend.dart';
import 'on_device.dart';
import 'translation_backend.dart';
import 'translator_setup_sheet.dart';
import '../../widgets/page_insets.dart';

/// The passage, what it was translated from and to, and the result.
///
/// Opens translating straight away — you asked by pressing the button, and a
/// sheet that then wants a second press to start would be asking twice. The
/// pickers re-run it: correcting a wrong guess is the reason *From* is a
/// control rather than a label.
class TranslateSheet extends StatefulWidget {
  const TranslateSheet({
    super.key,
    required this.passage,
    required this.settings,
    this.backend,
    this.resolve,
    this.onSaveAsNote,
  });

  final String passage;
  final ReaderSettings settings;

  /// Normally worked out from the platform — passed in only by tests, which
  /// have no phone to translate on.
  final TranslationBackend? backend;

  /// How the backend is found. Overridden by tests so they never shell out to
  /// whatever happens to be installed on the machine running them: the "nothing
  /// set up" state is a state to assert, not a property of the test runner.
  final Future<TranslationBackend?> Function()? resolve;

  /// Keeps the translation with the passage it came from, as a note on the
  /// book. Null where the caller has no annotation to hang it on.
  final Future<void> Function(String translation)? onSaveAsNote;

  @override
  State<TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<TranslateSheet> {
  /// Resolved once, on open, in privacy order: the device's own translator if
  /// this build has one *and* the reader has turned it on, then a translator
  /// installed on the machine, and only then the LibreTranslate address they
  /// named. The first two keep the passage here; the third is a server, so it
  /// is never reached for on its own.
  TranslationBackend? _backend;

  late TranslationLanguage _from = TranslationLanguage.auto;
  late TranslationLanguage _to = widget.settings.translateTo;

  String? _result;
  String? _error;

  /// True when there is no backend yet: a desktop with no server named, which
  /// is the state every desktop starts in.
  bool _needsSetup = false;
  bool _busy = false;
  bool _saved = false;

  /// What the backend decided the passage was, when it was asked to guess.
  /// Shown beside the picker so a wrong guess is visible *before* you read a
  /// translation and wonder why it is nonsense.
  TranslationLanguage? _detected;

  @override
  void initState() {
    super.initState();
    _resolveBackend();
  }

  Future<void> _resolveBackend() async {
    final resolved = widget.backend ??
        await (widget.resolve ??
            () async =>
                (onDeviceTranslationAvailable &&
                        widget.settings.useOnDeviceTranslation)
                    ? createOnDeviceBackend()
                    : await LocalTranslators.detect() ??
                        backendFor(
                          onDeviceAvailable: false,
                          libreUrl: widget.settings.translateUrl,
                          libreApiKey: widget.settings.translateApiKey,
                        ))();
    if (!mounted) return;
    setState(() => _backend = resolved);
    _run();
  }

  Future<void> _run() async {
    final backend = _backend;
    if (backend == null) {
      // Not a failure — it has not been set up yet, and the button that sets it
      // up is on this sheet. Saying so beats an error about a server nobody
      // named.
      setState(() {
        _busy = false;
        _result = null;
        _error = null;
        _needsSetup = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _needsSetup = false;
      _saved = false;
    });
    try {
      final translation = await backend.translate(
        widget.passage,
        from: _from,
        to: _to,
      );
      if (!mounted) return;
      setState(() {
        _result = translation.text;
        _detected = translation.detected;
        _busy = false;
      });
    } on TranslationException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _openLanguages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => onDeviceLanguagesSheet() ?? const TranslatorSetupSheet(),
    );
    if (!mounted) return;
    // A pack downloaded while the error was on screen is exactly the thing that
    // fixes it, so try again rather than leaving the message up.
    if (_error != null || _needsSetup) _resolveBackend();
  }

  Future<void> _save() async {
    final result = _result;
    final save = widget.onSaveAsNote;
    if (result == null || save == null) return;
    await save(result);
    if (!mounted) return;
    setState(() => _saved = true);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Translate', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          // The passage first: what you selected is what this is about, and a
          // mis-drag is quicker to spot here than in the translation.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                widget.passage,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _LanguagePicker(
                  label: 'From',
                  value: _from,
                  includeAuto: true,
                  detected: _detected,
                  onChanged: (value) {
                    setState(() {
                      _from = value;
                      _detected = null;
                    });
                    _run();
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 18),
              ),
              Expanded(
                child: _LanguagePicker(
                  label: 'To',
                  value: _to,
                  includeAuto: false,
                  onChanged: (value) {
                    setState(() => _to = value);
                    widget.settings.setTranslateTo(value);
                    _run();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_needsSetup)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    onDeviceTranslationAvailable &&
                            !widget.settings.useOnDeviceTranslation
                        ? 'This build can translate on the device using Google '
                            'ML Kit. It is proprietary, so it stays off until '
                            'you turn it on in the reader’s settings.'
                        : localEngineSupportedHere
                        ? 'No translator is installed on this machine. '
                            'Languages says what to install — it runs here, and '
                            'nothing is sent anywhere.'
                        : 'No translator here yet. Set a LibreTranslate address '
                            'in the reader’s settings, and passages go to that '
                            'server — yours, if you run one.',
                  ),
                ),
              ],
            )
          else if (_error != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            )
          else if (_result != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(_result!, style: theme.textTheme.bodyLarge),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _backend == null
                    ? 'nothing to translate with'
                    : 'via ${_backend!.name}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              // Everything about translation lives behind the button you
              // pressed to get here, including the packs: a language you are
              // missing is discovered *while translating*, so the way to fix it
              // belongs on this sheet rather than three screens away.
              TextButton.icon(
                onPressed: _openLanguages,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Languages'),
              ),
              if (_error != null)
                TextButton(onPressed: _busy ? null : _run, child: const Text('Try again')),
              if (_result != null) ...[
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _result!));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Translation copied')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
                if (widget.onSaveAsNote != null)
                  FilledButton.icon(
                    onPressed: _saved ? null : _save,
                    icon: Icon(_saved ? Icons.check : Icons.sticky_note_2_outlined,
                        size: 18),
                    label: Text(_saved ? 'Saved' : 'Save as note'),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.label,
    required this.value,
    required this.includeAuto,
    required this.onChanged,
    this.detected,
  });

  final String label;
  final TranslationLanguage value;
  final bool includeAuto;
  final TranslationLanguage? detected;
  final ValueChanged<TranslationLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      if (includeAuto) TranslationLanguage.auto,
      ...TranslationLanguage.all,
    ];
    return DropdownButtonFormField<TranslationLanguage>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        // The guess, said out loud. Without this a wrong detection is invisible
        // until the translation reads like nonsense.
        helperText: detected == null ? null : 'Detected ${detected!.name}',
      ),
      items: [
        for (final language in options)
          DropdownMenuItem(value: language, child: Text(language.name)),
      ],
      onChanged: (selected) {
        if (selected != null && selected != value) onChanged(selected);
      },
    );
  }
}
