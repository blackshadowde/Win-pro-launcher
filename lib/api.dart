import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One row of FreeLLMAPI's GET /v1/models.
class ModelInfo {
  final String id;
  final String name;

  /// Provider ("platform") id, e.g. groq, google, cerebras. Router entries
  /// such as `auto` are owned by `freellmapi`.
  final String provider;
  final bool available;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.available,
  });

  bool get isRouter =>
      provider == 'freellmapi' && (id == 'auto' || id.startsWith('auto:') || id == 'fusion');

  factory ModelInfo.fromJson(Map<String, dynamic> j) {
    final a = j['available'];
    final id = (j['id'] ?? '').toString();
    final name = j['name'];
    return ModelInfo(
      id: id,
      name: name is String && name.isNotEmpty ? name : id,
      provider: (j['owned_by'] ?? 'unknown').toString(),
      available: a == null || a == true || a == 1,
    );
  }
}

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// A piece of a streamed reply: text, or which provider/model answered.
class ChatChunk {
  final String? text;
  final String? via;
  const ChatChunk({this.text, this.via});
}

/// Client for FreeLLMAPI's OpenAI-compatible API on this phone.
class LlmApi {
  final String baseUrl;
  final String apiKey;
  LlmApi(this.baseUrl, this.apiKey);

  String get _root => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

  Future<List<ModelInfo>> models() async {
    final res = await http
        .get(Uri.parse('$_root/v1/models'), headers: _headers)
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) throw ApiException(res.statusCode, _errorText(res.body, res.statusCode));
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(ModelInfo.fromJson).toList();
  }

  /// Streams a chat completion. Cancelling the subscription stops the request.
  Stream<ChatChunk> chat({
    required String model,
    required List<Map<String, String>> messages,
  }) async* {
    final req = http.Request('POST', Uri.parse('$_root/v1/chat/completions'));
    req.headers.addAll({..._headers, 'Accept': 'text/event-stream'});
    req.body = jsonEncode({'model': model, 'messages': messages, 'stream': true});
    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw ApiException(res.statusCode, _errorText(body, res.statusCode));
      }
      var via = res.headers['x-routed-via'];
      if (via != null) yield ChatChunk(via: via);

      final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') break;
        Map<String, dynamic>? j;
        try {
          final d = jsonDecode(data);
          if (d is Map<String, dynamic>) j = d;
        } catch (_) {}
        if (j == null) continue;
        final err = j['error'];
        if (err != null) {
          throw ApiException(500, err is Map ? (err['message'] ?? err).toString() : err.toString());
        }
        if (via == null && j['model'] is String) {
          via = j['model'] as String;
          yield ChatChunk(via: via);
        }
        final choices = j['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          final delta = first is Map ? (first['delta'] ?? first['message']) : null;
          final content = delta is Map ? delta['content'] : null;
          if (content is String && content.isNotEmpty) yield ChatChunk(text: content);
        }
      }
    } finally {
      client.close();
    }
  }

  static String _errorText(String body, int status) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final e = j['error'];
        if (e is Map && e['message'] != null) return e['message'].toString();
        if (e != null) return e.toString();
        if (j['message'] != null) return j['message'].toString();
      }
    } catch (_) {}
    if (status == 401) return 'The API key was not accepted.';
    return 'Server answered $status.';
  }
}
