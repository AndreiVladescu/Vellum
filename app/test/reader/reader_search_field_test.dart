// The reader's search box: legible in every reader theme, and focusable from
// Ctrl+F even after the page has been clicked.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_hotkeys.dart';
import 'package:vellum/reader/reader_search_field.dart';
import 'package:vellum/reader/reader_settings.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

void main() {
  /// A bar with a search field in it, under an app theme that deliberately
  /// disagrees with the reader's (a dark app, a light page), and a separate
  /// focusable standing in for the PDF viewer.
  Future<
      ({
        TextEditingController controller,
        FocusNode search,
        FocusNode viewer,
      })> pump(
    WidgetTester tester, {
    required ReaderTheme readerTheme,
    ThemeData? appTheme,
    ValueChanged<String>? onChanged,
  }) async {
    final controller = TextEditingController();
    final search = FocusNode();
    final viewer = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(search.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: appTheme ?? ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: readerTheme.background,
          foregroundColor: readerTheme.foreground,
          title: ReaderSearchField(
            controller: controller,
            focusNode: search,
            foreground: readerTheme.foreground,
            onChanged: onChanged,
            onSubmitted: (_) {},
          ),
        ),
        body: Focus(focusNode: viewer, child: const SizedBox.expand()),
      ),
    ));
    return (controller: controller, search: search, viewer: viewer);
  }

  for (final theme in ReaderTheme.values) {
    testWidgets('${theme.name}: text, hint and caret come from the reader theme',
        (tester) async {
      await pump(tester, readerTheme: theme);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.color, theme.foreground);
      expect(field.cursorColor, theme.foreground);
      expect(field.decoration!.hintStyle!.color!.toARGB32() & 0x00ffffff,
          theme.foreground.toARGB32() & 0x00ffffff,
          reason: 'the hint is the same colour, only fainter');
      expect(field.decoration?.hintStyle?.color?.a, lessThan(1));
    });
  }

  testWidgets('a dark app over a light page still draws dark text',
      (tester) async {
    // The reported case: the field used the app theme's near-white text on a
    // white bar.
    await pump(tester, readerTheme: ReaderTheme.light);
    final text = tester.widget<EditableText>(find.byType(EditableText));
    expect(text.style.color, ReaderTheme.light.foreground);
    expect(text.style.color!.computeLuminance(), lessThan(0.2));
  });

  testWidgets('Ctrl+F reaches the box even when the viewer holds focus',
      (tester) async {
    final f = await pump(tester, readerTheme: ReaderTheme.light);
    f.viewer.requestFocus();
    await tester.pump();
    expect(f.viewer.hasPrimaryFocus, isTrue);

    focusSearchField(f.search, f.controller);
    await tester.pump();
    expect(f.search.hasPrimaryFocus, isTrue,
        reason: 'autofocus would have lost to the viewer here');
  });

  testWidgets('focusing again selects the old query, so typing replaces it',
      (tester) async {
    final f = await pump(tester, readerTheme: ReaderTheme.light);
    f.controller.text = 'whale';
    focusSearchField(f.search, f.controller);
    await tester.pump();

    expect(f.controller.selection.baseOffset, 0);
    expect(f.controller.selection.extentOffset, 5);

    await tester.enterText(find.byType(TextField), 'ahab');
    expect(f.controller.text, 'ahab');
  });

  testWidgets('Enter submits and leaves the caret in the box', (tester) async {
    final f = await pump(tester, readerTheme: ReaderTheme.light);
    focusSearchField(f.search, f.controller);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ahab');

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(f.search.hasPrimaryFocus, isTrue,
        reason: 'the next Enter must still be a next-match, not a dead key');
  });

  testWidgets('typing reports each change', (tester) async {
    final seen = <String>[];
    await pump(tester, readerTheme: ReaderTheme.sepia, onChanged: seen.add);
    await tester.enterText(find.byType(TextField), 'ahab');
    expect(seen, ['ahab']);
  });

  testWidgets('arrow keys go back to turning pages once the box is closed',
      (tester) async {
    // Closing the search must not leave the departed field holding focus: the
    // hotkeys step aside for any text field, so the keys would stay dead.
    final steps = <int>[];
    final hotkeys = ReaderHotkeys(
      isActive: () => true,
      onFind: () {},
      onGoTo: () {},
      onEscape: () => false,
      isPaged: () => true,
      onPageStep: steps.add,
      onNudge: (_) {},
    );
    final controller = TextEditingController();
    final search = FocusNode();
    final open = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(search.dispose);
    addTearDown(open.dispose);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (_, isOpen, _) => isOpen
              ? ReaderSearchField(
                  controller: controller,
                  focusNode: search,
                  foreground: Colors.black,
                  onSubmitted: (_) {},
                )
              : const SizedBox.shrink(),
        ),
      ),
    ));

    KeyEvent right() => KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowRight,
          logicalKey: LogicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        );

    focusSearchField(search, controller);
    await tester.pump();
    expect(hotkeys.handle(right()), isFalse, reason: 'caret keys, while typing');

    open.value = false;
    await tester.pump();
    expect(hotkeys.handle(right()), isTrue);
    expect(steps, [1]);
  });

  group('Debouncer', () {
    testWidgets('runs once, after the pause, with the last action',
        (tester) async {
      final ran = <String>[];
      final debounce = Debouncer(const Duration(milliseconds: 300));
      debounce.run(() => ran.add('a'));
      await tester.pump(const Duration(milliseconds: 200));
      debounce.run(() => ran.add('ab'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(ran, isEmpty, reason: 'the second keystroke restarted the wait');
      await tester.pump(const Duration(milliseconds: 150));
      expect(ran, ['ab']);
    });

    testWidgets('cancel drops what is waiting', (tester) async {
      final ran = <String>[];
      final debounce = Debouncer(const Duration(milliseconds: 300));
      debounce.run(() => ran.add('x'));
      debounce.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(ran, isEmpty);
    });
  });
}
