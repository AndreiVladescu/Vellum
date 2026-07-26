// Passphrase-encrypted backups (plan 5 #13). The tests that matter are the
// negative ones: an encryption that decrypts is easy, one that *refuses* a
// tampered or truncated file is the point.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/backup_crypto.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_backup_crypto'));
  tearDown(() => dir.deleteSync(recursive: true));

  File file(String name, List<int> bytes) =>
      File(p.join(dir.path, name))..writeAsBytesSync(bytes);

  List<int> noise(int length) {
    final random = Random(42);
    return [for (var i = 0; i < length; i++) random.nextInt(256)];
  }

  Future<List<int>> roundTrip(List<int> bytes, {String pass = 'a passphrase'}) async {
    final source = file('plain.bin', bytes);
    final sealed = File(p.join(dir.path, 'sealed.vbk'));
    final out = File(p.join(dir.path, 'out.bin'));
    await BackupCrypto.encryptFile(
        source: source, dest: sealed, passphrase: pass);
    await BackupCrypto.decryptFile(
        source: sealed, dest: out, passphrase: pass);
    return out.readAsBytesSync();
  }

  test('round-trips a small payload', () async {
    final bytes = noise(1234);
    expect(await roundTrip(bytes), bytes);
  });

  test('round-trips a payload spanning several chunks', () async {
    // Two and a bit chunks, so the counter, the chunk boundary and the short
    // final chunk are all exercised.
    final bytes = noise(BackupCrypto.chunkSize * 2 + 77);
    expect(await roundTrip(bytes), bytes);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('round-trips a payload that is exactly one chunk', () async {
    final bytes = noise(BackupCrypto.chunkSize);
    expect(await roundTrip(bytes), bytes);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('round-trips an empty payload', () async {
    expect(await roundTrip(const []), isEmpty);
  });

  test('the ciphertext does not contain the plaintext', () async {
    final marker = 'reader-notes-are-private';
    final source = file('plain.bin', [...marker.codeUnits, ...noise(500)]);
    final sealed = File(p.join(dir.path, 'sealed.vbk'));
    await BackupCrypto.encryptFile(
        source: source, dest: sealed, passphrase: 'pw');
    final raw = String.fromCharCodes(sealed.readAsBytesSync());
    expect(raw, isNot(contains(marker)));
    expect(raw, startsWith(BackupCrypto.magic));
  });

  test('two encryptions of the same file differ', () async {
    // A fresh salt and nonce prefix each time; identical archives would leak
    // "this backup is unchanged since the last one".
    final source = file('plain.bin', noise(2000));
    final a = File(p.join(dir.path, 'a.vbk'));
    final b = File(p.join(dir.path, 'b.vbk'));
    await BackupCrypto.encryptFile(source: source, dest: a, passphrase: 'pw');
    await BackupCrypto.encryptFile(source: source, dest: b, passphrase: 'pw');
    expect(a.readAsBytesSync(), isNot(b.readAsBytesSync()));
  });

  test('the wrong passphrase fails cleanly', () async {
    final source = file('plain.bin', noise(2000));
    final sealed = File(p.join(dir.path, 'sealed.vbk'));
    await BackupCrypto.encryptFile(
        source: source, dest: sealed, passphrase: 'right');
    await expectLater(
      BackupCrypto.decryptFile(
        source: sealed,
        dest: File(p.join(dir.path, 'out.bin')),
        passphrase: 'wrong',
      ),
      throwsA(isA<BackupDecryptException>()),
    );
  });

  test('a flipped byte in the ciphertext is refused', () async {
    final source = file('plain.bin', noise(2000));
    final sealed = File(p.join(dir.path, 'sealed.vbk'));
    await BackupCrypto.encryptFile(
        source: source, dest: sealed, passphrase: 'pw');
    final bytes = sealed.readAsBytesSync();
    bytes[bytes.length - 200] ^= 0xFF;
    sealed.writeAsBytesSync(bytes);
    await expectLater(
      BackupCrypto.decryptFile(
        source: sealed,
        dest: File(p.join(dir.path, 'out.bin')),
        passphrase: 'pw',
      ),
      throwsA(isA<BackupDecryptException>()),
    );
  });

  test('truncating the last chunk is refused, not silently accepted', () async {
    // The attack this closes: lopping the end off a multi-chunk backup would
    // otherwise decrypt happily into a shorter, valid-looking archive.
    final source = file('plain.bin', noise(BackupCrypto.chunkSize * 2 + 10));
    final sealed = File(p.join(dir.path, 'sealed.vbk'));
    await BackupCrypto.encryptFile(
        source: source, dest: sealed, passphrase: 'pw');
    final bytes = sealed.readAsBytesSync();
    sealed.writeAsBytesSync(
      bytes.sublist(0, bytes.length - (10 + 16)), // drop the final chunk
    );
    await expectLater(
      BackupCrypto.decryptFile(
        source: sealed,
        dest: File(p.join(dir.path, 'out.bin')),
        passphrase: 'pw',
      ),
      throwsA(isA<BackupDecryptException>()),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a plain zip is not mistaken for an encrypted backup', () async {
    final plain = file('plain.zip', [0x50, 0x4B, 0x03, 0x04, ...noise(100)]);
    expect(await BackupCrypto.isEncrypted(plain), isFalse);
    await expectLater(
      BackupCrypto.decryptFile(
        source: plain,
        dest: File(p.join(dir.path, 'out.bin')),
        passphrase: 'pw',
      ),
      throwsA(isA<BackupDecryptException>()),
    );
  });

  test('isEncrypted recognises our own output, and survives a tiny file',
      () async {
    final source = file('plain.bin', noise(64));
    final sealed = File(p.join(dir.path, 'sealed.vbk'));
    await BackupCrypto.encryptFile(
        source: source, dest: sealed, passphrase: 'pw');
    expect(await BackupCrypto.isEncrypted(sealed), isTrue);
    expect(await BackupCrypto.isEncrypted(file('tiny', [1, 2])), isFalse);
    expect(
      await BackupCrypto.isEncrypted(File(p.join(dir.path, 'missing'))),
      isFalse,
    );
  });
}
