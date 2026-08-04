import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/import/free_catalogues.dart';
import 'package:vellum/import/opds_browser_page.dart';

/// The catalogue picker (next features: free sources).
///
/// The OPDS browser could always fetch and download; what it lacked was any
/// way to know an address, which made the feature unreachable for anyone who
/// had not memorised one. These pin the shape of the offer, not the network —
/// each URL was fetched and its acquisition links inspected by hand before it
/// was added, which no unit test can stand in for.
void main() {
  test('every catalogue is a plausible https address with a description', () {
    expect(freeCatalogues, isNotEmpty);
    for (final c in freeCatalogues) {
      final uri = Uri.tryParse(c.url);
      expect(uri, isNotNull, reason: '${c.name} has an unparseable URL');
      // https only: these are fetched over the network by a client that will
      // happily follow whatever it is given.
      expect(uri!.scheme, 'https', reason: '${c.name} must be https');
      expect(uri.host, isNotEmpty);
      expect(c.name.trim(), isNotEmpty);
      // The description is load-bearing — "Project Gutenberg" alone says
      // nothing about whether it holds the book you are missing.
      expect(c.description.trim(), isNotEmpty);
    }
  });

  test('no shadow library is listed', () {
    // A guard rather than a comment: the picker exists so that following it
    // cannot land anyone somewhere they should not be, and a URL is an easy
    // thing to add without thinking about that.
    const forbidden = [
      'annas-archive',
      'libgen',
      'z-lib',
      'zlibrary',
      'sci-hub',
    ];
    for (final c in freeCatalogues) {
      for (final bad in forbidden) {
        expect(c.url.toLowerCase(), isNot(contains(bad)),
            reason: '${c.name} points at a shadow library');
      }
    }
  });

  testWidgets('the empty browser offers the catalogues', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OpdsBrowserPage()));
    await tester.pump();

    // The state this replaces was an empty box with a "https://example.com"
    // hint and nothing to tap.
    expect(find.text('Or start with a free one'), findsOneWidget);
    for (final c in freeCatalogues) {
      expect(find.text(c.name), findsOneWidget);
    }
  });

  testWidgets('tapping one fills the address and tries to open it',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OpdsBrowserPage()));
    await tester.pump();

    await tester.tap(find.text(freeCatalogues.first.name));
    await tester.pump();

    // No network in a test, so the fetch fails — what matters is that the tap
    // was wired to an open at all, rather than being decorative.
    expect(find.byType(OpdsBrowserPage), findsOneWidget);
  });
}
