import 'package:flutter/material.dart';

import '../data/database.dart';
import '../shortcuts.dart';

/// The Ctrl+K palette (plan 5 #26): every action in one list, plus every book
/// by title.
///
/// It exists as much for *discovery* as for speed — the shortcuts are only
/// useful once you know they're there, so each row shows its own key
/// combination. Books share the list rather than sitting in a second pane:
/// "the thing I want" is sometimes a command and sometimes a book, and asking
/// the user to know which before they start typing defeats the point.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.commands,
    required this.books,
    required this.onOpenBook,
  });

  final List<LibraryCommand> commands;

  /// The library, for jump-to-a-book. A stream so the palette can't show a
  /// book that was deleted while it was open.
  final Stream<List<Book>> books;
  final void Function(Book) onOpenBook;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Books whose title contains the query. Only once something is typed: an
  /// empty palette listing the whole library would bury the commands under it.
  List<Book> _matchingBooks(List<Book> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return all
        .where((b) => b.title.toLowerCase().contains(q))
        .take(20)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commands = matchCommands(widget.commands, _query);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Type a command, or a book title…',
                  icon: Icon(Icons.search),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: StreamBuilder<List<Book>>(
                stream: widget.books,
                builder: (context, snapshot) {
                  final books = _matchingBooks(snapshot.data ?? const []);
                  if (commands.isEmpty && books.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nothing matches “$_query”.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final command in commands)
                        _CommandRow(command: command),
                      if (books.isNotEmpty && commands.isNotEmpty)
                        const Divider(height: 1),
                      for (final book in books)
                        ListTile(
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(book.title),
                          subtitle: book.subtitle == null
                              ? null
                              : Text(book.subtitle!),
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onOpenBook(book);
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({required this.command});

  final LibraryCommand command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = shortcutLabelFor(command, meta: usesMetaModifier);
    return ListTile(
      leading: Icon(command.icon),
      title: Text(command.label),
      trailing: label == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(label, style: theme.textTheme.labelSmall),
            ),
      onTap: () {
        // Close first: most commands push a route or open a sheet, and doing
        // that under the palette would leave it stranded on top of the result.
        Navigator.of(context).pop();
        command.run();
      },
    );
  }
}
