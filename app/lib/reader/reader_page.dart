import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

/// The integrated PDF reader. Persists the current page as the user reads,
/// which drives the "Resume reading" state on the book's detail page.
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.book,
    required this.file,
    required this.repository,
  });

  final Book book;
  final File file;
  final LibraryRepository repository;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _controller = PdfViewerController();
  int? _page;
  int? _pageCount;

  void _onPageChanged(int? page) {
    if (page == null || !_controller.isReady) return;
    setState(() {
      _page = page;
      _pageCount = _controller.pageCount;
    });
    // Fire-and-forget; tiny row update, safe to do per page turn.
    widget.repository.saveReadingPosition(
        widget.book.id, page, _controller.pageCount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          if (_page != null && _pageCount != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('$_page / $_pageCount'),
              ),
            ),
        ],
      ),
      body: PdfViewer.file(
        widget.file.path,
        controller: _controller,
        initialPageNumber: widget.book.lastReadPage ?? 1,
        params: PdfViewerParams(onPageChanged: _onPageChanged),
      ),
    );
  }
}
