// Keyboard shortcuts and the command palette (plan 5 #26).
//
// The mapping is pure, so it's tested directly for both modifier conventions
// rather than only through whichever platform the CI machine happens to be.
// The palette gets widget tests, because what matters there is that a key
// event actually reaches it and that picking a row runs the right command.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/shortcuts.dart';

LibraryCommand _command(
  String id, {
  LogicalKeyboardKey? key,
  bool inPalette = true,
  VoidCallback? run,
}) =>
    LibraryCommand(
      id: id,
      label: id,
      icon: Icons.abc,
      key: key,
      inPalette: inPalette,
      run: run ?? () {},
    );

void main() {
  group('activators', () {
    test('a letter takes Ctrl off macOS and ⌘ on it', () {
      final add = _command('add', key: LogicalKeyboardKey.keyN);

      final ctrl = activatorFor(add, meta: false)!;
      expect(ctrl.control, isTrue);
      expect(ctrl.meta, isFalse);
      expect(shortcutLabelFor(add, meta: false), 'Ctrl+N');

      final cmd = activatorFor(add, meta: true)!;
      expect(cmd.meta, isTrue);
      expect(cmd.control, isFalse);
      expect(shortcutLabelFor(add, meta: true), '⌘N');
    });

    test('a function key carries no modifier on either platform', () {
      final sync = _command('sync', key: LogicalKeyboardKey.f5);
      for (final meta in [true, false]) {
        final activator = activatorFor(sync, meta: meta)!;
        expect(activator.control, isFalse);
        expect(activator.meta, isFalse);
        expect(shortcutLabelFor(sync, meta: meta), 'F5');
      }
    });

    test('Escape is bare, and reads as "Esc"', () {
      final clear = _command('clear', key: LogicalKeyboardKey.escape);
      final activator = activatorFor(clear, meta: false)!;
      expect(activator.control, isFalse);
      expect(shortcutLabelFor(clear, meta: false), 'Esc');
    });

    test('a command with no key gets no binding and no label', () {
      final scan = _command('scan');
      expect(activatorFor(scan, meta: false), isNull);
      expect(shortcutLabelFor(scan, meta: false), isNull);
      expect(shortcutsFor([scan], meta: false), isEmpty);
    });

    test('shortcutsFor binds every keyed command to its own callback', () {
      final fired = <String>[];
      final commands = [
        _command('add',
            key: LogicalKeyboardKey.keyN, run: () => fired.add('add')),
        _command('search',
            key: LogicalKeyboardKey.keyF, run: () => fired.add('search')),
        _command('scan', run: () => fired.add('scan')),
      ];
      final bindings = shortcutsFor(commands, meta: false);
      expect(bindings, hasLength(2), reason: 'the keyless command is skipped');
      // Looked up by trigger rather than by key equality: SingleActivator has
      // no value `==`, so two identical activators are different map keys.
      bindings.entries
          .firstWhere((e) =>
              (e.key as SingleActivator).trigger == LogicalKeyboardKey.keyF)
          .value();
      expect(fired, ['search']);
    });
  });

  group('palette filtering', () {
    final commands = [
      _command('Add a book'),
      _command('Import a folder'),
      _command('Preferences'),
      _command('Show all commands', inPalette: false),
    ];

    test('an empty query lists every palette command', () {
      expect(
        [for (final c in matchCommands(commands, '')) c.id],
        ['Add a book', 'Import a folder', 'Preferences'],
        reason: 'the inPalette: false command stays hidden',
      );
    });

    test('matching is case-insensitive and anywhere in the label', () {
      expect([for (final c in matchCommands(commands, 'FOLDER')) c.id],
          ['Import a folder']);
      expect([for (final c in matchCommands(commands, 'a ')) c.id],
          ['Add a book', 'Import a folder']);
    });

    test('no match yields an empty list, not everything', () {
      expect(matchCommands(commands, 'zzz'), isEmpty);
    });
  });

  group('bindings in a widget tree', () {
    testWidgets('a bound key runs its command', (tester) async {
      final fired = <String>[];
      final commands = [
        _command('add',
            key: LogicalKeyboardKey.keyN, run: () => fired.add('add')),
        _command('clear',
            key: LogicalKeyboardKey.escape, run: () => fired.add('clear')),
      ];
      await tester.pumpWidget(MaterialApp(
        home: CallbackShortcuts(
          bindings: shortcutsFor(commands, meta: false),
          child: const Focus(
            autofocus: true,
            child: Scaffold(body: SizedBox.expand()),
          ),
        ),
      ));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(fired, ['add']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(fired, ['add', 'clear']);
    });

    testWidgets('a focused text field still lets the shortcut through',
        (tester) async {
      // The binding a search box would break is exactly the one people press
      // while typing in it, so this is the case worth pinning.
      final fired = <String>[];
      final commands = [
        _command('add',
            key: LogicalKeyboardKey.keyN, run: () => fired.add('add')),
      ];
      await tester.pumpWidget(MaterialApp(
        home: CallbackShortcuts(
          bindings: shortcutsFor(commands, meta: false),
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      ));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(fired, ['add']);
    });
  });
}
