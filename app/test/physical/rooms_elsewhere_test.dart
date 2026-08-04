// Which published rooms a device offers to bring down.
//
// A room is a document on the server rather than a synced table (plan 5 #47),
// so a second device only learns about one if something asks. This is the rule
// behind that ask, and it has two halves that are easy to get backwards: your
// own rooms are the ones worth offering (someone else's are view-only and
// listed separately), and a room already arranged here must not be offered
// again — pressing it would overwrite this device's copy with the published
// one.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/physical/physical_libraries_page.dart';
import 'package:vellum/server/server_client.dart';

ServerLayout _layout(String id, {required bool mine, String? name}) =>
    ServerLayout(
      id: id,
      name: name ?? 'Room $id',
      revision: 3,
      publishedAt: '2026-08-04 10:00:00',
      mine: mine,
    );

void main() {
  test('a room published elsewhere is offered', () {
    final offered = roomsPublishedElsewhere([_layout('a', mine: true)], const {});
    expect(offered.map((l) => l.id), ['a']);
  });

  test('a room already on this device is not offered again', () {
    final offered = roomsPublishedElsewhere([_layout('a', mine: true)], {'a'});
    expect(offered, isEmpty, reason: 'bringing it down would overwrite this one');
  });

  test("someone else's room is never offered — it is view-only", () {
    final offered = roomsPublishedElsewhere([_layout('b', mine: false)], const {});
    expect(
      offered,
      isEmpty,
      reason: 'a shared room is a mirror, listed under "Shared with you"',
    );
  });

  test('a mixed list is split the way the two sections need', () {
    final all = [
      _layout('here', mine: true),
      _layout('elsewhere', mine: true),
      _layout('theirs', mine: false),
    ];
    expect(
      roomsPublishedElsewhere(all, {'here'}).map((l) => l.id),
      ['elsewhere'],
    );
  });

  test('nothing published means nothing to offer', () {
    expect(roomsPublishedElsewhere(const [], const {'here'}), isEmpty);
  });
}
