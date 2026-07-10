import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'physical_metrics.dart';

/// Bottom-sheet picker for choosing a library book to place in the room,
/// with a live title filter.
class BookPicker extends StatefulWidget {
  const BookPicker({super.key, required this.repository});
  final LibraryRepository repository;

  @override
  State<BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<BookPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Book>>(
      stream: widget.repository.watchAllBooks(),
      builder: (context, snap) {
        final q = _query.trim().toLowerCase();
        final books = [
          for (final b in snap.data ?? const <Book>[])
            if (q.isEmpty || b.title.toLowerCase().contains(q)) b,
        ];
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find a book to place…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: books.isEmpty
                    ? const Center(child: Text('No books.'))
                    : ListView.builder(
                        itemCount: books.length,
                        itemBuilder: (context, i) {
                          final b = books[i];
                          return ListTile(
                            leading: Container(
                              width: 12,
                              height: 34,
                              decoration: BoxDecoration(
                                color: PhysicalMetrics.color(b),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            title: Text(b.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: b.pageCount == null
                                ? null
                                : Text('${b.pageCount} pages'),
                            onTap: () => Navigator.pop(context, b),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
