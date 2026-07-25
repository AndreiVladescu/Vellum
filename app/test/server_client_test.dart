// VellumServerClient.capabilities() / Capabilities (plan 5 #6): the app's
// half of the capability handshake. sync_service_test.dart has the pattern
// this borrows (MockClient over VellumServerClient).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/server/server_client.dart';

void main() {
  test('capabilities() parses the server response and hits an unauthenticated GET',
      () async {
    http.Request? seen;
    final client = VellumServerClient(
      baseUrl: 'http://test',
      token: 't',
      httpClient: MockClient((req) async {
        seen = req;
        return http.Response(
          '{"server_version":"0.7.0","sync_protocol":3,'
          '"features":["delta_pull","groups"]}',
          200,
        );
      }),
    );

    final caps = await client.capabilities();

    expect(seen!.method, 'GET');
    expect(seen!.url.path, '/api/capabilities');
    // capabilities() is documented unauthenticated -- a client needs it
    // before it necessarily has a session -- so it must not send the bearer
    // header even though this client was built with a token.
    expect(seen!.headers.containsKey('authorization'), false);
    expect(caps.serverVersion, '0.7.0');
    expect(caps.syncProtocol, 3);
    expect(caps.features, ['delta_pull', 'groups']);
    expect(caps.hasFeature('groups'), true);
    expect(caps.hasFeature('batch_push'), false);
  });

  test('isNewerThanApp compares against kKnownSyncProtocol', () {
    expect(
      Capabilities(serverVersion: '1', syncProtocol: kKnownSyncProtocol, features: [])
          .isNewerThanApp,
      false,
      reason: 'equal protocol is not "newer"',
    );
    expect(
      Capabilities(serverVersion: '1', syncProtocol: kKnownSyncProtocol + 1, features: [])
          .isNewerThanApp,
      true,
    );
  });

  test('capabilities() throws ServerException on a non-2xx (e.g. a server predating it)',
      () async {
    final client = VellumServerClient(
      baseUrl: 'http://test',
      httpClient: MockClient(
        (req) async => http.Response('{"error":"not found"}', 404),
      ),
    );
    expect(client.capabilities(), throwsA(isA<ServerException>()));
  });
}
