// The Ctrl+K palette (plan 5 #26). The filtering rules live in
// `shortcuts_test.dart`; what this pins is the screen's own behaviour — that
// commands and books share one list, that a row runs the command it names, and
// that the palette closes before doing so (a command that pushes a route under
// an open dialog is the bug this prevents).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/shelf/command_palette.dart';
import 'package:vellum/shortcuts.dart';

void main() {
  final books = [
    Book(
      id: 'b1',
      title: 'Dune',
      needsPush: true,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    Book(
      id: 'b2',
      title: 'Neuromancer',
      needsPush: true,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  Future<List<String>> pumpPalette(
    WidgetTester tester, {
    required List<String> fired,
    required List<Book> opened,
  }) async {
    final commands = [
      LibraryCommand(
        id: 'add',
        label: 'Add a book',
        icon: Icons.add,
        run: () => fired.add('add'),
      ),
      LibraryCommand(
        id: 'import',
        label: 'Import a folder',
        icon: Icons.folder_open,
        run: () => fired.add('import'),
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: CommandPalette(
        commands: commands,
        books: Stream.value(books),
        onOpenBook: opened.add,
      ),
    ));
    await tester.pumpAndSettle();
    return [for (final c in commands) c.label];
  }

  testWidgets('opens listing every command, and no books until you type',
      (tester) async {
    await pumpPalette(tester, fired: [], opened: []);
    expect(find.text('Add a book'), findsOneWidget);
    expect(find.text('Import a folder'), findsOneWidget);
    expect(find.text('Dune'), findsNothing,
        reason: 'the whole library would bury the commands');
  });

  testWidgets('typing narrows the commands and surfaces matching books',
      (tester) async {
    await pumpPalette(tester, fired: [], opened: []);
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Neuromancer'), findsNothing);
    expect(find.text('Add a book'), findsNothing,
        reason: 'no command matches "dune"');
  });

  testWidgets('picking a command closes the palette, then runs it',
      (tester) async {
    final fired = <String>[];
    await pumpPalette(tester, fired: fired, opened: []);
    await tester.tap(find.text('Import a folder'));
    await tester.pumpAndSettle();

    expect(fired, ['import']);
    expect(find.byType(CommandPalette), findsNothing,
        reason: 'a command that pushes a route must not land under the dialog');
  });

  testWidgets('picking a book opens that book', (tester) async {
    final opened = <Book>[];
    await pumpPalette(tester, fired: [], opened: opened);
    await tester.enterText(find.byType(TextField), 'neuro');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neuromancer'));
    await tester.pumpAndSettle();

    expect([for (final b in opened) b.id], ['b2']);
  });

  testWidgets('a query matching nothing says so', (tester) async {
    await pumpPalette(tester, fired: [], opened: []);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing matches'), findsOneWidget);
  });
}
