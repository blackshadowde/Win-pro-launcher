import 'dart:convert';

import 'package:http/http.dart' as http;

import 'tools.dart';

/// A remote MCP server reached over "streamable HTTP" (JSON-RPC over POST).
/// Its tools become plugin tools named `mcp_<server>_<tool>`.
class McpServer extends Plugin {
  String label;
  String url;
  String token;
  bool enabled;

  final List<_McpTool> _tools = [];
  String? error;
  String? _session;
  int _nextId = 1;
  bool _connected = false;

  McpServer({required this.label, required this.url, this.token = '', this.enabled = true});

  factory McpServer.fromJson(Map<String, dynamic> j) => McpServer(
        label: (j['name'] ?? 'Server').toString(),
        url: (j['url'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        enabled: j['on'] != false,
      );

  Map<String, dynamic> toJson() => {'name': label, 'url': url, 'token': token, 'on': enabled};

  String get slug {
    final s = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'server' : (s.length > 20 ? s.substring(0, 20) : s);
  }

  @override
  String get id => 'mcp_$slug';
  @override
  String get name => label;
  @override
  String get description => _connected ? '${_tools.length} tools · $url' : (error ?? url);
  @override
  bool get ready => enabled && _connected && _tools.isNotEmpty;

  int get toolCount => _tools.length;
  bool get connected => _connected;

  String _toolName(String remote) {
    final n = 'mcp_${slug}_${remote.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
    return n.length > 64 ? n.substring(0, 64) : n;
  }

  @override
  List<ToolSpec> get tools => [
        for (final t in _tools)
          ToolSpec(_toolName(t.name), '[$label] ${t.description}', t.schema, writes: !t.readOnly),
      ];

  /// Connects and fetches the tool list. Sets [error] on failure.
  Future<void> connect() async {
    _connected = false;
    _session = null;
    _tools.clear();
    error = null;
    try {
      await _rpc('initialize', {
        'protocolVersion': '2025-03-26',
        'capabilities': {},
        'clientInfo': {'name': 'vibe-ai', 'version': '0.1'},
      });
      await _notify('notifications/initialized');
      String? cursor;
      do {
        final r = await _rpc('tools/list', {if (cursor != null) 'cursor': cursor});
        for (final t in (r['tools'] as List? ?? [])) {
          if (t is! Map) continue;
          final ann = t['annotations'];
          final schema = t['inputSchema'];
          _tools.add(_McpTool(
            (t['name'] ?? '').toString(),
            (t['description'] ?? '').toString(),
            schema is Map<String, dynamic> ? schema : {'type': 'object', 'properties': {}},
            ann is Map && ann['readOnlyHint'] == true,
          ));
        }
        cursor = r['nextCursor'] as String?;
      } while (cursor != null && cursor.isNotEmpty);
      _connected = true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
  }

  @override
  Future<String> run(String tool, Map<String, dynamic> args) async {
    final t = _tools.firstWhere((t) => _toolName(t.name) == tool, orElse: () => throw Exception('Unknown tool $tool'));
    Map<String, dynamic> r;
    try {
      r = await _rpc('tools/call', {'name': t.name, 'arguments': args});
    } catch (e) {
      // Session may have expired: reconnect once.
      await connect();
      if (!_connected) rethrow;
      r = await _rpc('tools/call', {'name': t.name, 'arguments': args});
    }
    final out = StringBuffer();
    for (final c in (r['content'] as List? ?? [])) {
      if (c is! Map) continue;
      if (c['type'] == 'text') {
        out.writeln(c['text']);
      } else if (c['type'] == 'resource' && c['resource'] is Map) {
        out.writeln((c['resource'] as Map)['text'] ?? '[resource ${(c['resource'] as Map)['uri']}]');
      } else {
        out.writeln('[${c['type']} content]');
      }
    }
    if (out.isEmpty && r['structuredContent'] != null) out.write(jsonEncode(r['structuredContent']));
    final text = out.toString().trim();
    if (r['isError'] == true) throw Exception(text.isEmpty ? 'The tool reported an error.' : text);
    return clip(text.isEmpty ? '(no output)' : text);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        if (_session != null) 'Mcp-Session-Id': _session!,
      };

  Future<void> _notify(String method) async {
    await http
        .post(Uri.parse(url), headers: _headers, body: jsonEncode({'jsonrpc': '2.0', 'method': method}))
        .timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> _rpc(String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    final res = await http
        .post(Uri.parse(url),
            headers: _headers, body: jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}))
        .timeout(const Duration(seconds: 60));
    final sid = res.headers['mcp-session-id'];
    if (sid != null && sid.isNotEmpty) _session = sid;
    if (res.statusCode == 401 || res.statusCode == 403) throw Exception('Not allowed (${res.statusCode}). Check the token.');
    if (res.statusCode >= 400) throw Exception('Server answered ${res.statusCode}.');
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final type = res.headers['content-type'] ?? '';
    Map<String, dynamic>? msg;
    if (type.contains('event-stream')) {
      for (final line in const LineSplitter().convert(body)) {
        if (!line.startsWith('data:')) continue;
        try {
          final j = jsonDecode(line.substring(5).trim());
          if (j is Map<String, dynamic> && j['id'] == id) msg = j;
        } catch (_) {}
      }
    } else {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) msg = j;
      if (j is List) {
        msg = j.whereType<Map<String, dynamic>>().firstWhere((m) => m['id'] == id, orElse: () => {});
      }
    }
    if (msg == null || msg.isEmpty) throw Exception('No answer to $method.');
    if (msg['error'] != null) {
      final e = msg['error'];
      throw Exception(e is Map ? (e['message'] ?? e.toString()) : e.toString());
    }
    final r = msg['result'];
    return r is Map<String, dynamic> ? r : <String, dynamic>{};
  }
}

class _McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> schema;
  final bool readOnly;
  _McpTool(this.name, this.description, this.schema, this.readOnly);
}
