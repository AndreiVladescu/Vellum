import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard shortcuts for the desktop app (plan 5 #26).
///
/// One list of [LibraryCommand]s is the single source of truth: it drives the
/// key bindings, the labels in tooltips, *and* the command palette. Adding an
/// action in one place therefore makes it reachable three ways instead of
/// leaving the palette and the bindings to drift apart.

/// Something the app can do, named the way a person would ask for it.
class LibraryCommand {
  const LibraryCommand({
    required this.id,
    required this.label,
    required this.icon,
    required this.run,
    this.key,
    this.inPalette = true,
  });

  /// Stable identifier — what tests match on, so renaming a label doesn't
  /// silently break a binding test.
  final String id;

  /// What the palette and the tooltip say.
  final String label;
  final IconData icon;
  final VoidCallback run;

  /// The letter (or function key) this command answers to, or null for a
  /// command that is only reachable from the palette. Combined with the
  /// platform's command modifier by [shortcutsFor].
  final LogicalKeyboardKey? key;

  /// False for commands that only make sense in context — clearing the search,
  /// or opening the palette from inside the palette.
  final bool inPalette;
}

/// True when this platform spells "the command modifier" as ⌘ rather than Ctrl.
bool get usesMetaModifier => defaultTargetPlatform == TargetPlatform.macOS;

/// The modifier's written form, for prose and tooltips: `⌘` or `Ctrl+`.
String commandModifierLabel({bool? meta}) =>
    (meta ?? usesMetaModifier) ? '⌘' : 'Ctrl+';

/// The activator for [command] on a platform whose modifier is [meta] or Ctrl.
///
/// Function keys (F5) carry no modifier: they are already unambiguous, and
/// requiring Ctrl+F5 would be inventing a convention nobody has.
SingleActivator? activatorFor(LibraryCommand command, {required bool meta}) {
  final key = command.key;
  if (key == null) return null;
  if (_isFunctionKey(key)) return SingleActivator(key);
  if (key == LogicalKeyboardKey.escape) return SingleActivator(key);
  return SingleActivator(key, control: !meta, meta: meta);
}

/// How a shortcut is written next to its menu item — "Ctrl+F", "⌘F", "F5".
String? shortcutLabelFor(LibraryCommand command, {required bool meta}) {
  final key = command.key;
  if (key == null) return null;
  final name = _keyLabel(key);
  if (_isFunctionKey(key) || key == LogicalKeyboardKey.escape) return name;
  return meta ? '⌘$name' : 'Ctrl+$name';
}

/// The binding map to hand to [CallbackShortcuts].
///
/// [meta] defaults to the running platform; tests pass it explicitly so the
/// mapping can be checked for both conventions on one machine.
Map<ShortcutActivator, VoidCallback> shortcutsFor(
  List<LibraryCommand> commands, {
  bool? meta,
}) {
  final useMeta = meta ?? usesMetaModifier;
  return {
    for (final command in commands) ?activatorFor(command, meta: useMeta): command.run,
  };
}

/// The commands matching [query], in the order they were declared.
///
/// Substring, case-insensitive, and over the whole label — the palette is a
/// filter, not a search engine, and someone typing "trash" should find "Open
/// the trash" without knowing it starts with "Open".
List<LibraryCommand> matchCommands(
  List<LibraryCommand> commands,
  String query,
) {
  final q = query.trim().toLowerCase();
  final visible = commands.where((c) => c.inPalette);
  if (q.isEmpty) return visible.toList();
  return visible.where((c) => c.label.toLowerCase().contains(q)).toList();
}

bool _isFunctionKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.f5 ||
    key == LogicalKeyboardKey.f1 ||
    key == LogicalKeyboardKey.f2 ||
    key == LogicalKeyboardKey.f3;

String _keyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.comma) return ',';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  // keyLabel is 'F' for keyF and 'F5' for f5 — already what we want to show.
  return key.keyLabel;
}
