import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Networking helpers for connecting to a self-hosted Vellum server whose TLS
/// certificate is self-signed (the default the server generates). Browsers and
/// the platform trust stores won't trust such a certificate, so the user
/// imports it in the app and we trust *exactly* that one.

/// Builds an [http.Client] that trusts a user-imported server certificate.
///
/// Two mechanisms together, so it works whether or not the server's hostname
/// matches the certificate:
///  1. the PEM is added as a trusted root, so a hostname matching a SAN
///     validates the normal way; and
///  2. a SHA-256 fingerprint check accepts the exact pinned certificate even
///     when the hostname doesn't match a SAN — the common case for a server
///     reached by bare LAN IP.
///
/// Falls back to a plain client (system trust only) when [pem] is null, blank,
/// or unparseable — so an https server with a real CA cert still works.
http.Client clientTrusting(String? pem) {
  final der = (pem == null || pem.isEmpty) ? null : firstCertDer(pem);
  if (pem == null || der == null) return http.Client();

  final pinned = sha256.convert(der).bytes;
  final context = SecurityContext(withTrustedRoots: true);
  try {
    context.setTrustedCertificatesBytes(utf8.encode(pem));
  } catch (_) {
    // Duplicate or malformed for the trust store — the fingerprint check below
    // is the real guard, so keep going.
  }
  final ioClient = HttpClient(context: context)
    ..badCertificateCallback = (cert, host, port) =>
        _bytesEqual(sha256.convert(cert.der).bytes, pinned);
  return IOClient(ioClient);
}

/// The SHA-256 fingerprint of the first certificate in [pem], formatted as
/// `AB:CD:…` uppercase hex — identical to what the server logs on startup and
/// to `openssl x509 -fingerprint -sha256`, so the user can compare them.
/// Returns null when no certificate can be parsed (used to validate imports).
String? fingerprintOf(String pem) {
  final der = firstCertDer(pem);
  if (der == null) return null;
  return [
    for (final b in sha256.convert(der).bytes)
      b.toRadixString(16).padLeft(2, '0').toUpperCase(),
  ].join(':');
}

/// Decodes the first `-----BEGIN CERTIFICATE-----` block of [pem] to DER bytes.
/// Null when there's no complete block or its body isn't valid base64.
List<int>? firstCertDer(String pem) {
  const begin = '-----BEGIN CERTIFICATE-----';
  const end = '-----END CERTIFICATE-----';
  final s = pem.indexOf(begin);
  if (s < 0) return null;
  final e = pem.indexOf(end, s + begin.length);
  if (e < 0) return null;
  final body = pem.substring(s + begin.length, e).replaceAll(RegExp(r'\s'), '');
  try {
    return base64.decode(body);
  } catch (_) {
    return null;
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
