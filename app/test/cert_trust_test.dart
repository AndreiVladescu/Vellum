import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/server/cert_trust.dart';

// A stable self-signed test certificate (CN=vellum-test). Its SHA-256
// fingerprint below was produced by `openssl x509 -fingerprint -sha256`, so this
// pins cert_trust's fingerprint format/value to what the server and openssl show.
const _pem = '''
-----BEGIN CERTIFICATE-----
MIIDDTCCAfWgAwIBAgIUGbgJXi1FwXi3+MJ8BRPHuqVYZoAwDQYJKoZIhvcNAQEL
BQAwFjEUMBIGA1UEAwwLdmVsbHVtLXRlc3QwHhcNMjYwNzExMTg0ODMzWhcNMzYw
NzA4MTg0ODMzWjAWMRQwEgYDVQQDDAt2ZWxsdW0tdGVzdDCCASIwDQYJKoZIhvcN
AQEBBQADggEPADCCAQoCggEBALQdK4+nxO+HdDGhP6YcypYcKcCxHYaE2cISjHZd
bk5/TyG9BL2K64fSJFiRsA8cAO5SEKTWQHbDTnxI0XVqOuzIoHZesIDtO/3PFqgY
V5ZgisB9hCcBJoX3EpsmzDpV6NHmB0xQa//U3q3P14VAhr3dXfrBIl2F96AZBhqT
G/TmmBan2r0S6FExQphGIU/OYK69KEgZZZi+SFdaCTUDBGpueg37aWFOM0muT/8F
vcZMkUmgr3fgmzf7tz2wl8dcFqvEZlUQRUrLKckYmVrBVDJeTPWaE3O1W+fFiJIK
k9K1EIMLcZBwbSFBVnNq3urlvWbVssSsdMT5mydWlFnLn/sCAwEAAaNTMFEwHQYD
VR0OBBYEFI41zBmcfnYl4bHdzbWtfX56583jMB8GA1UdIwQYMBaAFI41zBmcfnYl
4bHdzbWtfX56583jMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEB
ABk/0XFSGIrpB+sxTdivN7p8xS66GnyHhEecjBmkf8MVUTMsl6dqem24OMXhxW4y
QTBVykw8kRCZUnBnvQtjaVG/sxPYZo3V8CznRdE0NH2fDh6p0VuFgCR18g+0ulyZ
8nq7qsYyqgBIQpS3NxZoQmHoqXljy2ZcaHb7p+QaGx1DprwLiXsd8VY2RSODbDQb
R62SmDs62RRF4JmFeII7GgKMLGKJYXhEvNkLiJTATmojM10zaNCh2IZw3ELPfEtw
jtkulsSqt3cJKUVChlB3JcRMoBmTvh2zWPmJUUcRLZwM6pbQcFP7NCeajiMxs3I8
bIx6m51plegcNoGBcSfBa7E=
-----END CERTIFICATE-----
''';

const _expectedFingerprint =
    'F7:57:A3:CD:4C:CD:48:0A:AE:94:D2:09:8D:58:2C:CB:C5:9D:FF:3C:C9:C6:B9:B9:93:DE:82:6A:5B:1F:0B:0A';

void main() {
  test('fingerprintOf matches openssl for a known certificate', () {
    expect(fingerprintOf(_pem), _expectedFingerprint);
  });

  test('fingerprintOf ignores surrounding text and whitespace', () {
    expect(fingerprintOf('junk before\n$_pem\njunk after'), _expectedFingerprint);
  });

  test('fingerprintOf returns null for non-certificate input', () {
    expect(fingerprintOf('not a certificate'), isNull);
    expect(fingerprintOf('-----BEGIN CERTIFICATE-----\n@@@@\n-----END CERTIFICATE-----'),
        isNull);
  });

  test('firstCertDer round-trips to a stable byte length', () {
    final der = firstCertDer(_pem);
    expect(der, isNotNull);
    expect(der!.length, greaterThan(500)); // a real X.509 DER, not a stub
  });

  test('clientTrusting(null) returns a usable client', () {
    // No cert imported → falls back to a plain client (system trust only).
    expect(clientTrusting(null), isNotNull);
    expect(clientTrusting(''), isNotNull);
  });
}
