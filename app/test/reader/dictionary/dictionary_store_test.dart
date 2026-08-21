// Getting the dictionary onto the device.
//
// The install is the part that can go wrong quietly: half an archive unpacked
// looks exactly like a working dictionary until the first lookup of a verb. So
// what is pinned here is that only the wanted files are kept, that the
// 15 MB index nothing reads is left behind, and that anything that is not a
// WordNet database is refused rather than half-installed.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/dictionary/dictionary_store.dart';

/// A stand-in for Princeton's tarball: the same layout, tiny contents.
File writeArchive(Directory dir, Iterable<String> names) {
  final archive = Archive();
  for (final name in names) {
    final bytes = utf8.encode('  1 licence\ndog n 1 0 1 0 00000012\n');
    archive.add(ArchiveFile.bytes('dict/$name', bytes));
  }
  final tar = TarEncoder().encodeBytes(archive);
  final file = File('${dir.path}/WNdb-3.0.tar.gz')
    ..writeAsBytesSync(GZipEncoder().encodeBytes(tar));
  return file;
}

void main() {
  late Directory dir;
  late DictionaryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vellum_dict');
    store = DictionaryStore(Directory('${dir.path}/dictionary'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('nothing is installed until it is', () {
    expect(store.isInstalled, false);
    expect(store.bytesOnDisk, 0);
  });

  test('unpacks the files a lookup needs', () async {
    await store.installFromArchive(writeArchive(dir, [
      ...['index.noun', 'data.noun', 'index.verb', 'data.verb'],
      ...['index.adj', 'data.adj', 'index.adv', 'data.adv'],
    ]));

    expect(store.isInstalled, true);
    expect(store.bytesOnDisk, greaterThan(0));
    expect(File('${store.dir.path}/data.verb').existsSync(), true);
  });

  test('leaves behind the files nothing reads', () async {
    await store.installFromArchive(writeArchive(dir, [
      ...['index.noun', 'data.noun', 'index.verb', 'data.verb'],
      ...['index.adj', 'data.adj', 'index.adv', 'data.adv'],
      // A third of the archive, and never opened.
      'index.sense',
      'cntlist.rev',
    ]));

    expect(File('${store.dir.path}/index.sense').existsSync(), false,
        reason: 'a 15 MB file nothing reads has no business on a phone');
    expect(store.isInstalled, true);
  });

  test('keeps the irregular forms when the archive has them', () async {
    await store.installFromArchive(writeArchive(dir, [
      ...['index.noun', 'data.noun', 'index.verb', 'data.verb'],
      ...['index.adj', 'data.adj', 'index.adv', 'data.adv'],
      ...['noun.exc', 'verb.exc'],
    ]));

    expect(File('${store.dir.path}/verb.exc').existsSync(), true);
  });

  test('refuses an archive that is missing half the database', () async {
    // Princeton's own download has no `.exc` files, so a partial archive is a
    // real thing to meet — and a dictionary that answers for nouns and not
    // verbs is worse than one that says it failed.
    final archive = writeArchive(dir, ['index.noun', 'data.noun']);

    await expectLater(
      store.installFromArchive(archive),
      throwsA(isA<DictionaryInstallException>()),
    );
    expect(store.isInstalled, false);
  });

  test('refuses something that is not a WordNet archive at all', () async {
    final notAnArchive = File('${dir.path}/holiday.jpg')
      ..writeAsBytesSync([1, 2, 3, 4, 5]);

    await expectLater(
      store.installFromArchive(notAnArchive),
      throwsA(anything),
    );
    expect(store.isInstalled, false);
  });

  test('removing it gives the space back, and it can come again', () async {
    final archive = writeArchive(dir, [
      ...['index.noun', 'data.noun', 'index.verb', 'data.verb'],
      ...['index.adj', 'data.adj', 'index.adv', 'data.adv'],
    ]);
    await store.installFromArchive(archive);

    await store.remove();
    expect(store.isInstalled, false);
    expect(store.bytesOnDisk, 0);

    await store.installFromArchive(archive);
    expect(store.isInstalled, true);
  });

  test('the install leaves no temporary files behind', () async {
    await store.installFromArchive(writeArchive(dir, [
      ...['index.noun', 'data.noun', 'index.verb', 'data.verb'],
      ...['index.adj', 'data.adj', 'index.adv', 'data.adv'],
    ]));

    final leftovers = store.dir
        .listSync()
        .map((e) => e.path.split('/').last)
        .where((name) => name.startsWith('.'));
    expect(leftovers, isEmpty,
        reason: 'the unpacked tar is 34 MB — it cannot be left lying about');
  });
}
