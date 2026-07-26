import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Optional passphrase encryption for backup archives (plan 5 #13).
///
/// **Why it exists.** A backup is the whole library — including `readerNotes`,
/// which never leave the device through sync precisely because they're personal
/// — and on Android it travels through the share sheet to wherever the user
/// taps. A plain zip on someone else's cloud drive is a different privacy
/// posture from the one the rest of Vellum keeps.
///
/// **Why it is optional and off by default.** A plain `.zip` can be opened by
/// anything, forever, with no software of ours. That inspectability is worth
/// keeping as the default; encryption is for when you know you want it, and
/// **nothing about the passphrase is stored** — lose it and the backup is gone.
///
/// ## Container format
///
/// ```text
/// "VELLUMBK"        8 bytes magic
/// 0x01              1 byte  format version
/// uint32be          header length
/// header            UTF-8 JSON: KDF parameters, salt, nonce prefix, chunk size
/// chunk*            ciphertext(n) ‖ MAC(16) for each plaintext chunk
/// ```
///
/// **Chunked, not one buffer.** A library can be tens of gigabytes; encrypting
/// it as a single AES-GCM message would mean holding all of it in memory at
/// once. Each chunk gets its own nonce (`prefix ‖ counter`) and its own MAC.
///
/// The authenticated data for every chunk is `header ‖ counter ‖ isLast`, which
/// is what makes the *sequence* tamper-evident and not just the bytes: chunks
/// can't be reordered (the counter is authenticated), can't be spliced in from
/// another backup (the header carries this file's salt and nonce prefix), and
/// the file can't be truncated (the final chunk is the only one authenticated
/// with `isLast = 1`).
class BackupCrypto {
  const BackupCrypto._();

  static const magic = 'VELLUMBK';
  static const _version = 1;

  /// 1 MiB plaintext per chunk: big enough that the per-chunk 16-byte MAC and
  /// the algorithm setup are noise, small enough to stream comfortably.
  static const chunkSize = 1024 * 1024;

  /// Argon2id at OWASP's 64 MiB / 3-pass setting, measured at well under a
  /// second on a laptop — a cost paid once per backup, not per book.
  static const _memoryKiB = 65536;
  static const _iterations = 3;
  static const _parallelism = 1;

  static const _saltBytes = 16;
  static const _noncePrefixBytes = 8;
  static const _macBytes = 16;

  /// Whether [file] is one of ours, by reading only the magic.
  static Future<bool> isEncrypted(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final head = await handle.read(magic.length);
      return head.length == magic.length &&
          utf8.decode(head, allowMalformed: true) == magic;
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  /// Encrypts [source] into [dest] under [passphrase].
  static Future<void> encryptFile({
    required File source,
    required File dest,
    required String passphrase,
  }) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      [for (var i = 0; i < _saltBytes; i++) random.nextInt(256)],
    );
    final noncePrefix = Uint8List.fromList(
      [for (var i = 0; i < _noncePrefixBytes; i++) random.nextInt(256)],
    );
    final header = utf8.encode(jsonEncode({
      'kdf': 'argon2id',
      'm': _memoryKiB,
      't': _iterations,
      'p': _parallelism,
      'salt': base64.encode(salt),
      'noncePrefix': base64.encode(noncePrefix),
      'chunk': chunkSize,
    }));
    final key = await _deriveKey(passphrase, salt, _memoryKiB, _iterations,
        _parallelism);
    final gcm = AesGcm.with256bits();

    final input = await source.open();
    final output = dest.openWrite();
    try {
      output
        ..add(utf8.encode(magic))
        ..add([_version])
        ..add(_uint32(header.length))
        ..add(header);

      final total = await source.length();
      var offset = 0;
      var counter = 0;
      // An empty source still writes one (empty, final) chunk, so a truncated
      // file and an empty one stay distinguishable.
      do {
        final plain = await input.read(chunkSize);
        offset += plain.length;
        final isLast = offset >= total;
        final box = await gcm.encrypt(
          plain,
          secretKey: key,
          nonce: _nonce(noncePrefix, counter),
          aad: _aad(header, counter, isLast: isLast),
        );
        output
          ..add(box.cipherText)
          ..add(box.mac.bytes);
        counter++;
        if (isLast) break;
      } while (true);
      await output.flush();
    } finally {
      await input.close();
      await output.close();
    }
  }

  /// Decrypts [source] into [dest].
  ///
  /// Throws [BackupDecryptException] for a wrong passphrase, a truncated file,
  /// or any tampering — deliberately one exception for all of them, because
  /// distinguishing "wrong passphrase" from "corrupt file" tells an attacker
  /// which of the two they achieved, and tells the user nothing they can act on
  /// differently.
  static Future<void> decryptFile({
    required File source,
    required File dest,
    required String passphrase,
  }) async {
    final input = await source.open();
    IOSink? output;
    try {
      final head = await input.read(magic.length + 1 + 4);
      if (head.length < magic.length + 5 ||
          utf8.decode(head.sublist(0, magic.length), allowMalformed: true) !=
              magic) {
        throw const BackupDecryptException('not an encrypted Vellum backup');
      }
      if (head[magic.length] != _version) {
        throw const BackupDecryptException(
          'this backup was written by a newer version of Vellum',
        );
      }
      final headerLength = ByteData.sublistView(
        Uint8List.fromList(head),
        magic.length + 1,
      ).getUint32(0);
      if (headerLength <= 0 || headerLength > 4096) {
        throw const BackupDecryptException('backup header is not readable');
      }
      final header = await input.read(headerLength);
      if (header.length != headerLength) {
        throw const BackupDecryptException('backup header is truncated');
      }
      final Map<String, dynamic> params;
      try {
        params = jsonDecode(utf8.decode(header)) as Map<String, dynamic>;
      } catch (_) {
        throw const BackupDecryptException('backup header is not readable');
      }
      if (params['kdf'] != 'argon2id') {
        throw const BackupDecryptException('unsupported key derivation');
      }

      final salt = base64.decode(params['salt'] as String);
      final noncePrefix = base64.decode(params['noncePrefix'] as String);
      final chunk = (params['chunk'] as num).toInt();
      if (chunk <= 0 || chunk > 64 * 1024 * 1024) {
        throw const BackupDecryptException('backup header is not readable');
      }
      final key = await _deriveKey(
        passphrase,
        salt,
        (params['m'] as num).toInt(),
        (params['t'] as num).toInt(),
        (params['p'] as num).toInt(),
      );
      final gcm = AesGcm.with256bits();

      final total = await source.length();
      var consumed = magic.length + 1 + 4 + headerLength;
      var counter = 0;
      output = dest.openWrite();
      do {
        final stored = await input.read(chunk + _macBytes);
        if (stored.length < _macBytes) {
          throw const BackupDecryptException('backup is truncated');
        }
        consumed += stored.length;
        final isLast = consumed >= total;
        final cipherText = stored.sublist(0, stored.length - _macBytes);
        final mac = Mac(stored.sublist(stored.length - _macBytes));
        final List<int> plain;
        try {
          plain = await gcm.decrypt(
            SecretBox(cipherText, nonce: _nonce(noncePrefix, counter), mac: mac),
            secretKey: key,
            aad: _aad(header, counter, isLast: isLast),
          );
        } on SecretBoxAuthenticationError {
          throw const BackupDecryptException(
            'wrong passphrase, or the backup has been damaged',
          );
        }
        output.add(plain);
        counter++;
        if (isLast) break;
      } while (true);
      await output.flush();
    } finally {
      await input.close();
      await output?.close();
    }
  }

  static Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt,
    int memoryKiB,
    int iterations,
    int parallelism,
  ) =>
      Argon2id(
        memory: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: 32,
      ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  static List<int> _nonce(List<int> prefix, int counter) =>
      [...prefix, ..._uint32(counter)];

  static List<int> _aad(List<int> header, int counter, {required bool isLast}) =>
      [...header, ..._uint32(counter), isLast ? 1 : 0];

  static List<int> _uint32(int value) {
    final bytes = ByteData(4)..setUint32(0, value);
    return bytes.buffer.asUint8List();
  }
}

/// A backup that could not be decrypted: wrong passphrase, tampering, or a
/// truncated file — see [BackupCrypto.decryptFile] for why they're one type.
class BackupDecryptException implements Exception {
  const BackupDecryptException(this.message);

  final String message;

  @override
  String toString() => message;
}
