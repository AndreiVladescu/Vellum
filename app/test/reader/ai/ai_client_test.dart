// Sending a passage to a model (request 8/19 #10: "send it to an ai, be it
// commercial or self-hosted").
//
// One request shape covers both halves of that request, so what is pinned here
// is the shape: the address people actually paste, the body the servers expect,
// the key sent only when there is one, and the far end's own error text coming
// through instead of a status code.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/reader/ai/ai_client.dart';

/// A server that records what it was asked and answers what it is told to.
({MockClient client, List<http.Request> seen}) fake(
  http.Response Function(http.Request) reply,
) {
  final seen = <http.Request>[];
  return (
    client: MockClient((request) async {
      seen.add(request);
      return reply(request);
    }),
    seen: seen,
  );
}

http.Response answer(String text) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': text},
          },
        ],
      }),
      200,
    );

void main() {
  group('the address people paste', () {
    test('a bare host gets the OpenAI path — Ollama’s own default', () {
      expect(chatCompletionsUri('http://localhost:11434').toString(),
          'http://localhost:11434/v1/chat/completions');
    });

    test('one that already ends in /v1 is not given a second one', () {
      expect(chatCompletionsUri('https://api.openai.com/v1').toString(),
          'https://api.openai.com/v1/chat/completions');
    });

    test('the whole endpoint is left alone', () {
      expect(
          chatCompletionsUri('https://example.com/v1/chat/completions')
              .toString(),
          'https://example.com/v1/chat/completions');
    });

    test('trailing slashes and spaces are forgiven', () {
      expect(chatCompletionsUri('  http://localhost:1234/v1/  ').toString(),
          'http://localhost:1234/v1/chat/completions');
    });
  });

  group('the request', () {
    test('carries the model, the passage and the question', () async {
      final server = fake((_) => answer('It means the spice trade.'));
      final client = AiClient(
        baseUrl: 'http://localhost:11434',
        model: 'llama3.2',
        client: server.client,
      );

      final reply = await client.ask(
        passage: 'The spice must flow',
        question: 'What does this mean?',
        bookTitle: 'Dune',
      );

      expect(reply, 'It means the spice trade.');
      final body = jsonDecode(server.seen.single.body) as Map;
      expect(body['model'], 'llama3.2');
      expect(body['stream'], false, reason: 'the sheet waits for one answer');
      final messages = (body['messages'] as List).cast<Map>();
      expect(messages.first['role'], 'system');
      expect(messages.last['content'], contains('The spice must flow'));
      expect(messages.last['content'], contains('What does this mean?'));
      expect(messages.last['content'], contains('Dune'),
          reason: 'the book is context the model cannot get from the passage');
    });

    test('sends no key when there is none — a local model wants none',
        () async {
      final server = fake((_) => answer('fine'));
      await AiClient(
        baseUrl: 'http://localhost:11434',
        model: 'llama3.2',
        client: server.client,
      ).ask(passage: 'p', question: 'q');

      expect(server.seen.single.headers.containsKey('authorization'), false);
    });

    test('sends the key when there is one', () async {
      final server = fake((_) => answer('fine'));
      await AiClient(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        apiKey: 'sk-test',
        client: server.client,
      ).ask(passage: 'p', question: 'q');

      expect(server.seen.single.headers['authorization'], 'Bearer sk-test');
    });

    test('cuts a passage that would cost a fortune to send', () async {
      final server = fake((_) => answer('fine'));
      await AiClient(
        baseUrl: 'http://localhost:11434',
        model: 'llama3.2',
        client: server.client,
      ).ask(passage: 'x' * 100000, question: 'q');

      final body = jsonDecode(server.seen.single.body) as Map;
      final sent = (body['messages'] as List).last['content'] as String;
      expect(sent.length, lessThan(maxPassageCharacters + 500));
      expect(sent, contains('…'), reason: 'and it says it was cut');
    });
  });

  group('when it goes wrong', () {
    Future<void> expectMessage(http.Response response, Matcher matcher) async {
      final client = AiClient(
        baseUrl: 'http://localhost:11434',
        model: 'llama3.2',
        client: MockClient((_) async => response),
      );
      await expectLater(
        client.ask(passage: 'p', question: 'q'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', matcher)),
      );
    }

    test('the server’s own words come through', () async {
      await expectMessage(
        http.Response(
          jsonEncode({
            'error': {'message': 'model "llama9" not found'},
          }),
          404,
        ),
        contains('llama9'),
      );
    });

    test('a refused key says so', () async {
      await expectMessage(http.Response('nope', 401), contains('key'));
    });

    test('an unreachable server names the address', () async {
      final client = AiClient(
        baseUrl: 'http://localhost:11434',
        model: 'llama3.2',
        client: MockClient((_) async => throw const SocketFailure()),
      );
      await expectLater(
        client.ask(passage: 'p', question: 'q'),
        throwsA(isA<AiException>().having(
            (e) => e.message, 'message', contains('localhost:11434'))),
      );
    });

    test('an empty answer is an error, not a blank sheet', () async {
      await expectMessage(answer('   '), contains('nothing'));
    });

    test('an answer in a shape we do not know is an error too', () async {
      await expectMessage(
        http.Response(jsonEncode({'unexpected': true}), 200),
        contains('nothing'),
      );
    });
  });
}

/// Stands in for a dead socket without dragging dart:io into the test.
class SocketFailure implements Exception {
  const SocketFailure();
  @override
  String toString() => 'Connection refused';
}
