import 'dart:convert';

import 'package:http/http.dart' as http;

import 'tools.dart';

/// Lets the AI open a web page and read its text.
class WebPlugin extends Plugin {
  @override
  String get id => 'web';
  @override
  String get name => 'Web page reader';
  @override
  String get description => 'Open a link and read the page text.';
  @override
  bool get ready => true;

  @override
  List<ToolSpec> get tools => [
        ToolSpec(
          'web_read',
          'Download a web page (http/https URL) and return its readable text.',
          schema({'url': str('Full URL starting with http:// or https://')}, ['url']),
        ),
      ];

  @override
  Future<String> run(String tool, Map<String, dynamic> args) async {
    final url = (args['url'] ?? '').toString().trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw Exception('Not a web address: $url');
    }
    final r = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Android) VibeAI/0.1',
      'Accept': 'text/html,text/plain,application/json;q=0.9,*/*;q=0.5',
    }).timeout(const Duration(seconds: 30));
    if (r.statusCode >= 400) throw Exception('The page answered ${r.statusCode}.');
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final type = r.headers['content-type'] ?? '';
    if (!type.contains('html')) return clip(body);
    return clip(htmlToText(body));
  }
}

/// Rough HTML → text: drops scripts/styles/tags, keeps line breaks, decodes common entities.
String htmlToText(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<(script|style|noscript|svg|head)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  s = s.replaceAll(RegExp(r'<\s*(br|/p|/div|/li|/h[1-6]|/tr)\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
  const entities = {'&nbsp;': ' ', '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'"};
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
  return s.trim();
}
