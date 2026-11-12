import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../settings/app_settings.dart';
import 'reading_goals.dart';

/// Opens the reading goals dialog and saves what the reader chose.
Future<void> showGoalsDialog(
  BuildContext context,
  AppSettingsStore settings,
) async {
  final result = await showDialog<({int? books, int? minutes})>(
    context: context,
    builder: (_) => _GoalsDialog(
      books: settings.readingGoalBooks,
      minutes: settings.readingGoalMinutes,
    ),
  );
  if (result == null) return;
  await settings.setReadingGoals(books: result.books, minutes: result.minutes);
}

class _GoalsDialog extends StatefulWidget {
  const _GoalsDialog({required this.books, required this.minutes});

  final int? books;
  final int? minutes;

  @override
  State<_GoalsDialog> createState() => _GoalsDialogState();
}

class _GoalsDialogState extends State<_GoalsDialog> {
  late int? _books = widget.books;
  late int? _minutes = widget.minutes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.goalsDialogTitle),
      // Scrollable: at a large text size the two pickers outgrow the dialog.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GoalPicker(
              label: l10n.goalsBooksLabel,
              customLabel: l10n.goalsBooksCustomLabel,
              presets: ReadingGoals.bookPresets,
              max: ReadingGoals.maxBooks,
              value: _books,
              presetLabel: (n) => '$n', // i18n-ignore
              onChanged: (v) => _books = v,
            ),
            const SizedBox(height: 20),
            _GoalPicker(
              label: l10n.goalsMinutesLabel,
              customLabel: l10n.goalsMinutesCustomLabel,
              presets: ReadingGoals.minutePresets,
              max: ReadingGoals.maxMinutes,
              value: _minutes,
              presetLabel: l10n.insightsMinutesShort,
              onChanged: (v) => _minutes = v,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (books: _books, minutes: _minutes)),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// "No goal", the presets, and "Other" with a free number.
///
/// "No goal" is a chip of its own, the first one, so switching a goal off is
/// one tap and not "delete the number and hope". The picked value is reported
/// through [onChanged] without rebuilding the dialog: the chips keep their
/// own selection state.
class _GoalPicker extends StatefulWidget {
  const _GoalPicker({
    required this.label,
    required this.customLabel,
    required this.presets,
    required this.max,
    required this.value,
    required this.presetLabel,
    required this.onChanged,
  });

  final String label;
  final String customLabel;
  final List<int> presets;
  final int max;
  final int? value;
  final String Function(int) presetLabel;
  final ValueChanged<int?> onChanged;

  @override
  State<_GoalPicker> createState() => _GoalPickerState();
}

enum _Choice { none, preset, other }

class _GoalPickerState extends State<_GoalPicker> {
  late _Choice _choice;
  int? _preset;
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    if (v == null) {
      _choice = _Choice.none;
    } else if (widget.presets.contains(v)) {
      _choice = _Choice.preset;
      _preset = v;
    } else {
      _choice = _Choice.other;
    }
    _text = TextEditingController(
        text: _choice == _Choice.other ? '$v' : ''); // i18n-ignore
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(_Choice choice, {int? preset}) {
    setState(() {
      _choice = choice;
      _preset = preset;
    });
    widget.onChanged(switch (choice) {
      _Choice.none => null,
      _Choice.preset => preset,
      _Choice.other => ReadingGoals.normalise(int.tryParse(_text.text),
          max: widget.max),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n.goalsNone),
              selected: _choice == _Choice.none,
              onSelected: (_) => _pick(_Choice.none),
            ),
            for (final n in widget.presets)
              ChoiceChip(
                label: Text(widget.presetLabel(n)),
                selected: _choice == _Choice.preset && _preset == n,
                onSelected: (_) => _pick(_Choice.preset, preset: n),
              ),
            ChoiceChip(
              label: Text(l10n.goalsOther),
              selected: _choice == _Choice.other,
              onSelected: (_) => _pick(_Choice.other),
            ),
          ],
        ),
        if (_choice == _Choice.other) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: widget.customLabel,
              helperText: l10n.goalsCustomHelper(widget.max),
            ),
            onChanged: (text) => widget.onChanged(ReadingGoals.normalise(
                int.tryParse(text),
                max: widget.max)),
          ),
        ],
      ],
    );
  }
}
