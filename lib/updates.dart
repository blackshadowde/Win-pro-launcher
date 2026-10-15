import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Checks this repo's latest GitHub Release (published by the Build APK workflow).
class Updates {
  static const repo = 'blackshadowde/Win-pro-launcher';

  static Future<int> currentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  }

  /// Returns the newer release, or null when you're up to date.
  static Future<UpdateInfo?> check() async {
    final res = await http
        .get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null; // no release published yet
    if (res.statusCode != 200) throw Exception('GitHub answered ${res.statusCode}');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] ?? '').toString();
    final build = int.tryParse(tag.split('.').last) ?? 0;
    if (build <= await currentBuild()) return null;
    String? apk;
    for (final a in (j['assets'] as List? ?? const [])) {
      final url = a is Map ? a['browser_download_url'] : null;
      if (url is String && url.endsWith('.apk')) apk = url;
    }
    return UpdateInfo(
      version: tag,
      downloadUrl: apk ?? (j['html_url'] ?? '').toString(),
      notes: (j['body'] ?? '').toString(),
    );
  }
}

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String notes;
  const UpdateInfo({required this.version, required this.downloadUrl, required this.notes});
}
