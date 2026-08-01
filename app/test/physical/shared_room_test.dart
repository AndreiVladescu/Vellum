// Rooms shared with you, in the app (next features #9).
//
// The gap this closes: `/api/layouts` has always returned rooms shared with the
// caller, and the console drew them, but the app only knew about rooms this
// device had published. So the browser showed more of your library than the app
// did.
//
// A shared room is a *mirror* — fetched and drawn, never written to the local
// tables — which is what these check: the geometry comes off the wire, the
// titles come from the separate endpoint, and a book you cannot see is drawn
// anonymously rather than left as a hole.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/physical/shared_room_page.dart';
import 'package:vellum/server/server_client.dart';

/// A one-shelf room with two books, in the published document format.
Map<String, dynamic> _doc() => {
      'doc': 'vellum.layout',
      'version': 1,
      'environment': {'id': 'env-1', 'name': 'The study'},
      'shelves': [
        {
          'id': 's1',
          'x1': 0.0,
          'y1': 1.0,
          'x2': 0.9,
          'y2': 1.0,
          'label': 'Top shelf',
          'kind': 'shelf',
        },
      ],
      'placements': [
        {
          'id': 'p1',
          'copy_id': 'c1',
          'book_id': 'b1',
          'x': 0.0,
          'y': 1.0,
          'rotation': 0,
          'width_m': 0.04,
          'height_m': 0.2,
        },
        {
          'id': 'p2',
          'copy_id': 'c2',
          'book_id': 'secret',
          'x': 0.05,
          'y': 1.0,
          'rotation': 0,
          'width_m': 0.04,
          'height_m': 0.2,
        },
      ],
    };

void main() {
  /// A client backed by a fake server. [titles] is what `/books` answers;
  /// passing null makes that endpoint fail, which must not break the room.
  VellumServerClient client({
    Map<String, dynamic>? doc,
    List<Map<String, dynamic>>? titles,
  }) {
    final mock = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/books')) {
        if (titles == null) return http.Response('nope', 500);
        return http.Response(jsonEncode(titles), 200,
            headers: {'content-type': 'application/json'});
      }
      if (doc == null) return http.Response('gone', 404);
      return http.Response(
        jsonEncode({
          'id': 'l1',
          'name': 'The study',
          'revision': 3,
          'published_at': '2026-08-01 10:00:00',
          'mine': false,
          'doc': doc,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    return VellumServerClient(
      baseUrl: 'http://test.local',
      token: 't',
      httpClient: mock,
    );
  }

  Future<void> pump(WidgetTester tester, VellumServerClient c) async {
    await tester.pumpWidget(MaterialApp(
      home: SharedRoomPage(client: c, layoutId: 'l1', name: 'The study'),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('draws the room and says it is not yours to edit', (tester) async {
    await pump(
      tester,
      client(doc: _doc(), titles: [
        {'book_id': 'b1', 'title': 'Dune', 'authors': <String>[], 'has_cover': false},
      ]),
    );

    expect(find.text('The study'), findsOneWidget);
    expect(find.text('Shared with you · view only'), findsOneWidget);
    // Two placements are drawn, including the one whose title we can't see.
    expect(find.byType(Tooltip), findsNWidgets(2));
    expect(
      find.byTooltip('Dune'),
      findsOneWidget,
      reason: 'the title should come from the separate books endpoint',
    );
    expect(
      find.byTooltip('A book you cannot see'),
      findsOneWidget,
      reason: 'a book not shared with you is drawn, not left as a hole',
    );
  });

  testWidgets('a failed title lookup still draws the room', (tester) async {
    // The document is the room; the titles are a bonus. Losing the bonus must
    // not lose the room.
    await pump(tester, client(doc: _doc(), titles: null));
    expect(find.byType(Tooltip), findsNWidgets(2));
    expect(find.byTooltip('A book you cannot see'), findsNWidgets(2));
  });

  testWidgets('says it needs the server rather than showing an empty room',
      (tester) async {
    await pump(tester, client(doc: null));
    expect(
      find.textContaining('needs a connection'),
      findsOneWidget,
      reason: 'a mirror is useless offline, and should say so',
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}
