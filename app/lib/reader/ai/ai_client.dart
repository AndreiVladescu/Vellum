/// Sending a passage to a model (request 8/19 #10: "a way to get the text out
/// of the pdf/epub and send it to an ai, be it commercial or self-hosted").
///
/// One shape of request, not a list of providers: OpenAI's `/chat/completions`,
/// which Ollama, LM Studio, llama.cpp, vLLM, OpenRouter and OpenAI itself all
/// answer. So "self-hosted" and "commercial" are the same code path with a
/// different address in it, and a model that appears next year needs no release
/// of this app.
///
/// Nothing here is on by default. A passage sent to a model *leaves the
/// device*, which is the opposite of everything else the reader does, so it
/// happens only after someone has typed an address in themselves.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the chat endpoint is, given whatever the reader typed.
///
/// People paste what their tool showed them: `http://localhost:11434`,
/// `http://localhost:1234/v1`, or the whole endpoint. All three mean the same
/// server, and being wrong about it looks like the model is down.
Uri chatCompletionsUri(String baseUrl) {
  var base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.endsWith('/chat/completions')) return Uri.parse(base);
  if (base.endsWith('/v1')) return Uri.parse('$base/chat/completions');
  return Uri.parse('$base/v1/chat/completions');
}

/// How much of a passage is worth sending.
///
/// A chapter can be a hundred thousand characters; every model has a limit and
/// most bill by the token. Cutting it here — visibly, with the sheet saying so
/// — beats an opaque error from the far end, or a bill.
const maxPassageCharacters = 12000;

String trimPassage(String passage) => passage.length <= maxPassageCharacters
    ? passage
    : '${passage.substring(0, maxPassageCharacters)}…';

class AiException implements Exception {
  const AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiClient {
  AiClient({
    required this.baseUrl,
    required this.model,
    this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String model;
  final String? apiKey;
  final http.Client _client;

  /// The instruction the model gets before the passage. Kept short and stated
  /// here rather than hidden in the UI: it is the one part of the request the
  /// reader did not write.
  static const systemPrompt =
      'You are helping someone reading a book. Answer about the passage they '
      'give you, briefly and plainly. If the passage does not say, say so '
      'rather than guessing.';

  Future<String> ask({
    required String passage,
    required String question,
    String? bookTitle,
  }) async {
    final content = [
      if (bookTitle != null && bookTitle.isNotEmpty) 'From “$bookTitle”.',
      'Passage:\n${trimPassage(passage)}',
      '\n$question',
    ].join('\n');

    late final http.Response response;
    try {
      response = await _client.post(
        chatCompletionsUri(baseUrl),
        headers: {
          'content-type': 'application/json',
          if (apiKey != null && apiKey!.isNotEmpty)
            'authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'stream': false,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': content},
          ],
        }),
      );
    } catch (e) {
      throw AiException('Could not reach $baseUrl — $e');
    }

    if (response.statusCode != 200) {
      throw AiException(_errorFrom(response));
    }
    final answer = _answerFrom(response.body);
    if (answer == null || answer.trim().isEmpty) {
      throw const AiException('The model answered with nothing.');
    }
    return answer.trim();
  }

  void close() => _client.close();

  /// The far end's own words where it gives any — `{"error":{"message":…}}` is
  /// what every one of these servers returns, and it usually says exactly what
  /// is wrong ("model not found", "invalid api key").
  static String _errorFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final error = body['error'];
        final message = error is Map ? error['message'] : error;
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {
      // Not JSON — fall through to the status line.
    }
    return switch (response.statusCode) {
      401 || 403 => 'The server refused the key.',
      404 => 'No model endpoint at that address.',
      _ => 'The server answered ${response.statusCode}.',
    };
  }

  static String? _answerFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final message = (choices.first as Map)['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
      // Some servers answer the older completion shape.
      final text = (choices.first as Map)['text'];
      return text is String ? text : null;
    } catch (_) {
      return null;
    }
  }
}
