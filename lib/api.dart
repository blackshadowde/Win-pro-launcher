import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

  bool get isAutoChain => provider == 'freellmapi' && (id == 'auto' || id.startsWith('auto:'));

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

/// A piece of a streamed reply: text, which provider/model answered, or part of a tool call.
class ChatChunk {
  final String? text;
  final String? via;
  final ToolDelta? tool;
  const ChatChunk({this.text, this.via, this.tool});
}

/// A streamed fragment of a tool call. Fragments with the same [index] belong together.
class ToolDelta {
  final int index;
  final String? id;
  final String? name;
  final String arguments;
  const ToolDelta(this.index, this.id, this.name, this.arguments);
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
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  }) async* {
    final req = http.Request('POST', Uri.parse('$_root/v1/chat/completions'));
    req.headers.addAll({..._headers, 'Accept': 'text/event-stream'});
    req.body = jsonEncode({
      'model': model,
      'messages': messages,
      'stream': true,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
    });
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
          final calls = delta is Map ? delta['tool_calls'] : null;
          if (calls is List) {
            for (var i = 0; i < calls.length; i++) {
              final c = calls[i];
              if (c is! Map) continue;
              final f = c['function'];
              final args = f is Map ? f['arguments'] : null;
              yield ChatChunk(
                tool: ToolDelta(
                  c['index'] is int ? c['index'] as int : i,
                  c['id'] as String?,
                  f is Map ? f['name'] as String? : null,
                  args is String ? args : (args == null ? '' : jsonEncode(args)),
                ),
              );
            }
          }
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

/// One generated image: raw bytes plus which provider/model made it.
class GeneratedImages {
  final List<Uint8List> images;
  final String? via;
  const GeneratedImages(this.images, this.via);
}

extension ImageGeneration on LlmApi {
  /// POST /v1/images/generations with the router's default image model.
  Future<GeneratedImages> generateImage(String prompt) async {
    final res = await http
        .post(
          Uri.parse('$_root/v1/images/generations'),
          headers: _headers,
          body: jsonEncode({'prompt': prompt, 'n': 1}),
        )
        .timeout(const Duration(seconds: 120));
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, LlmApi._errorText(res.body, res.statusCode));
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final out = <Uint8List>[];
    final data = j is Map ? j['data'] : null;
    if (data is List) {
      for (final item in data) {
        if (item is! Map) continue;
        final b64 = item['b64_json'];
        final url = item['url'];
        if (b64 is String && b64.isNotEmpty) {
          out.add(base64Decode(b64));
        } else if (url is String && url.startsWith('data:')) {
          out.add(base64Decode(url.substring(url.indexOf(',') + 1)));
        } else if (url is String && url.isNotEmpty) {
          final img = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
          if (img.statusCode == 200) out.add(img.bodyBytes);
        }
      }
    }
    if (out.isEmpty) throw ApiException(502, 'No image came back. Is an image provider key added?');
    final provider = j is Map ? j['provider'] : null;
    final model = j is Map ? j['model'] : null;
    final via = provider is String && model is String ? '$provider/$model' : (model is String ? model : null);
    return GeneratedImages(out, via);
  }
}

/// Health of one provider key, from the dashboard's /api/keys.
class KeyHealth {
  final String provider;
  final String status; // healthy | rate_limited | invalid | error | unknown
  final bool enabled;
  final String? error;
  const KeyHealth(this.provider, this.status, this.enabled, this.error);
}

/// The dashboard's admin API (/api/*), signed in with a session token.
class DashboardApi {
  final String baseUrl;
  final String token;
  DashboardApi(this.baseUrl, this.token);

  String get _root => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  /// Signs in with the dashboard email and password; returns the session token.
  static Future<String> login(String baseUrl, String email, String password) async {
    final root = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final res = await http
        .post(
          Uri.parse('$root/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw ApiException(res.statusCode, LlmApi._errorText(res.body, res.statusCode));
    final j = jsonDecode(res.body);
    final token = j is Map ? j['token'] : null;
    if (token is! String || token.isEmpty) throw ApiException(500, 'Sign-in gave no token.');
    return token;
  }

  Future<dynamic> _get(String path) async {
    final res = await http.get(Uri.parse('$_root$path'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw ApiException(res.statusCode, LlmApi._errorText(res.body, res.statusCode));
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$_root$path'));
    req.headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw ApiException(res.statusCode, LlmApi._errorText(res.body, res.statusCode));
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<String?> unifiedKey() async {
    final j = await _get('/api/settings/api-key');
    final k = j is Map ? j['apiKey'] : null;
    return k is String ? k : null;
  }

  /// Current routing settings (strategy, peak hours, ...), as the server returns them.
  Future<Map<String, dynamic>> routing() async {
    final j = await _get('/api/fallback/routing');
    return j is Map<String, dynamic> ? j : <String, dynamic>{};
  }

  /// Changes only the strategy; sends the other routing settings back unchanged.
  Future<void> setStrategy(String strategy, Map<String, dynamic> current) async {
    final body = <String, dynamic>{'strategy': strategy};
    for (final k in [
      'exploreEnabled',
      'keySelectionStrategy',
      'cooldownCeilingMs',
      'peakHoursAdjust',
      'peakStartHour',
      'peakEndHour',
      'peakTimezone',
    ]) {
      if (current[k] != null) body[k] = current[k];
    }
    await _send('PUT', '/api/fallback/routing', body);
  }

  Future<List<KeyHealth>> keys() async {
    final j = await _get('/api/keys');
    if (j is! List) return const [];
    return j.whereType<Map>().map((k) {
      return KeyHealth(
        (k['platform'] ?? 'unknown').toString(),
        (k['status'] ?? 'unknown').toString(),
        k['enabled'] != false,
        k['lastHealthError']?.toString(),
      );
    }).toList();
  }

  Future<void> checkAllKeys() async {
    await _send('POST', '/api/health/check-all');
  }
}
