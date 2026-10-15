import 'dart:convert';

import 'package:http/http.dart' as http;

import 'tools.dart';

/// GitHub through its REST API, with your personal access token.
class GitHubPlugin extends Plugin {
  final String token;
  GitHubPlugin(this.token);

  static const _base = 'https://api.github.com';
  String? _login;

  @override
  String get id => 'github';
  @override
  String get name => 'GitHub';
  @override
  String get description => 'Repos, files, commits, issues, pull requests and Actions builds.';
  @override
  bool get ready => token.trim().isNotEmpty;

  static final _repo = str('Repository as "owner/name", or just "name" for one of your own repos');

  @override
  List<ToolSpec> get tools => [
        ToolSpec('github_list_repos', 'List your repositories, most recently updated first.',
            schema({'limit': integer('How many (default 30, max 100)')})),
        ToolSpec('github_list_files', 'List files and folders at a path in a repository.',
            schema({'repo': _repo, 'path': str('Folder path, empty for the root'), 'ref': str('Branch or commit (optional)')},
                ['repo'])),
        ToolSpec('github_read_file', 'Read a text file from a repository.',
            schema({'repo': _repo, 'path': str('File path'), 'ref': str('Branch or commit (optional)')},
                ['repo', 'path'])),
        ToolSpec('github_search_code', 'Search code across GitHub, or within one repository.',
            schema({'query': str('Search words'), 'repo': str('Limit to this repository (optional)')}, ['query'])),
        ToolSpec('github_recent_commits', 'Recent commits on a branch.',
            schema({'repo': _repo, 'branch': str('Branch (optional)'), 'limit': integer('How many (default 10)')},
                ['repo'])),
        ToolSpec('github_list_issues', 'List issues or pull requests.',
            schema({
              'repo': _repo,
              'kind': {'type': 'string', 'enum': ['issues', 'pulls'], 'description': 'issues or pulls'},
              'state': {'type': 'string', 'enum': ['open', 'closed', 'all'], 'description': 'Default open'},
            }, ['repo'])),
        ToolSpec('github_actions_runs', 'Latest GitHub Actions workflow runs (builds) with their result.',
            schema({'repo': _repo, 'limit': integer('How many (default 5)')}, ['repo'])),
        ToolSpec('github_run_failures',
            'Why an Actions run failed: failed jobs and steps, error annotations and the end of the failed job logs.',
            schema({'repo': _repo, 'run_id': integer('Run id from github_actions_runs')}, ['repo', 'run_id'])),
        ToolSpec('github_create_issue', 'Create an issue.',
            schema({'repo': _repo, 'title': str('Title'), 'body': str('Description (Markdown)')}, ['repo', 'title']),
            writes: true),
        ToolSpec('github_comment', 'Comment on an issue or pull request.',
            schema({'repo': _repo, 'number': integer('Issue or PR number'), 'body': str('Comment (Markdown)')},
                ['repo', 'number', 'body']),
            writes: true),
        ToolSpec(
            'github_commit_file',
            'Create or replace a whole file and commit it. Send the complete new file content.',
            schema({
              'repo': _repo,
              'path': str('File path'),
              'content': str('Complete new file content'),
              'message': str('Commit message'),
              'branch': str('Branch (optional, default branch if empty)'),
            }, ['repo', 'path', 'content', 'message']),
            writes: true),
      ];

  @override
  String describe(String tool, Map<String, dynamic> args) {
    final repo = args['repo'] ?? '';
    return switch (tool) {
      'github_list_repos' => 'List your repos',
      'github_list_files' => 'List files in $repo/${args['path'] ?? ''}',
      'github_read_file' => 'Read $repo/${args['path']}',
      'github_search_code' => 'Search code: ${args['query']}',
      'github_recent_commits' => 'Recent commits in $repo',
      'github_list_issues' => 'List ${args['kind'] ?? 'issues'} in $repo',
      'github_actions_runs' => 'Latest builds of $repo',
      'github_run_failures' => 'Why run ${args['run_id']} of $repo failed',
      'github_create_issue' => 'Create issue in $repo: ${args['title']}',
      'github_comment' => 'Comment on $repo #${args['number']}',
      'github_commit_file' => 'Commit $repo/${args['path']}: ${args['message']}',
      _ => super.describe(tool, args),
    };
  }

  // ---- HTTP ---------------------------------------------------------------------------------

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ${token.trim()}',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$_base$path'), headers: _headers).timeout(const Duration(seconds: 30));
    if (r.statusCode >= 300) throw Exception('GitHub ${r.statusCode}: ${_message(r.body)}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<String> _getText(String path) async {
    final r = await http.get(Uri.parse('$_base$path'), headers: _headers).timeout(const Duration(seconds: 60));
    if (r.statusCode >= 300) throw Exception('GitHub ${r.statusCode}: ${_message(r.body)}');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  Future<dynamic> _send(String method, String path, Map<String, dynamic> body) async {
    final req = http.Request(method, Uri.parse('$_base$path'))
      ..headers.addAll({..._headers, 'Content-Type': 'application/json'})
      ..body = jsonEncode(body);
    final r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
    if (r.statusCode >= 300) throw Exception('GitHub ${r.statusCode}: ${_message(r.body)}');
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  static String _message(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['message'] != null) return j['message'].toString();
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  /// Your GitHub username; checks the token works.
  Future<String> whoAmI() async {
    if (token.trim().isEmpty) throw Exception('Add a token first.');
    _login = ((await _get('/user')) as Map)['login'].toString();
    return _login!;
  }

  Future<String> _fullRepo(dynamic repo) async {
    final r = (repo ?? '').toString().trim();
    if (r.isEmpty) throw Exception('Which repository?');
    if (r.contains('/')) return r;
    _login ??= ((await _get('/user')) as Map)['login'].toString();
    return '$_login/$r';
  }

  static String _q(Object? v) => Uri.encodeQueryComponent((v ?? '').toString());
  static String _path(Object? v) =>
      (v ?? '').toString().split('/').where((p) => p.isNotEmpty).map(Uri.encodeComponent).join('/');

  // ---- Tools --------------------------------------------------------------------------------

  @override
  Future<String> run(String tool, Map<String, dynamic> a) async {
    switch (tool) {
      case 'github_list_repos':
        final n = ((a['limit'] as num?)?.toInt() ?? 30).clamp(1, 100);
        final list = await _get('/user/repos?sort=updated&per_page=$n') as List;
        return list
            .map((r) => '${r['full_name']}${r['private'] == true ? ' (private)' : ''}'
                ' · ${r['default_branch']} · updated ${r['updated_at']}'
                '${r['description'] != null ? ' · ${r['description']}' : ''}')
            .join('\n');

      case 'github_list_files':
        final repo = await _fullRepo(a['repo']);
        final ref = (a['ref'] ?? '').toString();
        final j = await _get('/repos/$repo/contents/${_path(a['path'])}${ref.isEmpty ? '' : '?ref=${_q(ref)}'}');
        if (j is! List) return 'That path is a file. Use github_read_file.';
        return j.map((f) => '${f['type'] == 'dir' ? '[dir] ' : ''}${f['path']}'
            '${f['type'] == 'file' ? ' (${f['size']} bytes)' : ''}').join('\n');

      case 'github_read_file':
        final repo = await _fullRepo(a['repo']);
        final ref = (a['ref'] ?? '').toString();
        final j = await _get('/repos/$repo/contents/${_path(a['path'])}${ref.isEmpty ? '' : '?ref=${_q(ref)}'}');
        if (j is List) return 'That path is a folder. Use github_list_files.';
        final content = (j['content'] ?? '').toString().replaceAll('\n', '');
        if (content.isEmpty) return 'The file is empty or too large to read through the API.';
        final text = utf8.decode(base64Decode(content), allowMalformed: true);
        return clip(text, 30000);

      case 'github_search_code':
        final repo = (a['repo'] ?? '').toString().trim();
        final q = '${a['query']}${repo.isEmpty ? '' : ' repo:${await _fullRepo(repo)}'}';
        final j = await _get('/search/code?per_page=20&q=${_q(q)}') as Map;
        final items = (j['items'] as List? ?? []);
        if (items.isEmpty) return 'No results.';
        return items.map((i) => '${i['repository']['full_name']}: ${i['path']}').join('\n');

      case 'github_recent_commits':
        final repo = await _fullRepo(a['repo']);
        final n = ((a['limit'] as num?)?.toInt() ?? 10).clamp(1, 50);
        final branch = (a['branch'] ?? '').toString();
        final list = await _get('/repos/$repo/commits?per_page=$n${branch.isEmpty ? '' : '&sha=${_q(branch)}'}') as List;
        return list.map((c) {
          final msg = (c['commit']['message'] ?? '').toString().split('\n').first;
          return '${(c['sha'] as String).substring(0, 7)} · ${c['commit']['author']['date']} · $msg';
        }).join('\n');

      case 'github_list_issues':
        final repo = await _fullRepo(a['repo']);
        final pulls = a['kind'] == 'pulls';
        final state = (a['state'] ?? 'open').toString();
        final list = await _get('/repos/$repo/${pulls ? 'pulls' : 'issues'}?state=${_q(state)}&per_page=30') as List;
        final rows = list.where((i) => pulls || i['pull_request'] == null);
        if (rows.isEmpty) return 'None.';
        return rows.map((i) => '#${i['number']} [${i['state']}] ${i['title']} · by ${i['user']['login']}').join('\n');

      case 'github_actions_runs':
        final repo = await _fullRepo(a['repo']);
        final n = ((a['limit'] as num?)?.toInt() ?? 5).clamp(1, 20);
        final j = await _get('/repos/$repo/actions/runs?per_page=$n') as Map;
        final runs = (j['workflow_runs'] as List? ?? []);
        if (runs.isEmpty) return 'No workflow runs.';
        return runs.map((r) => 'run ${r['id']} · ${r['name']} #${r['run_number']} · ${r['status']}'
            '${r['conclusion'] != null ? '/${r['conclusion']}' : ''} · ${r['head_branch']} · ${r['created_at']}').join('\n');

      case 'github_run_failures':
        final repo = await _fullRepo(a['repo']);
        final runId = a['run_id'];
        final jobs = ((await _get('/repos/$repo/actions/runs/$runId/jobs?per_page=50')) as Map)['jobs'] as List? ?? [];
        final failed = jobs.where((j) => j['conclusion'] == 'failure').toList();
        if (failed.isEmpty) return 'No failed jobs in run $runId.';
        final out = StringBuffer();
        for (final job in failed.take(2)) {
          out.writeln('Job: ${job['name']}');
          for (final s in (job['steps'] as List? ?? [])) {
            if (s['conclusion'] == 'failure') out.writeln('  Failed step: ${s['name']}');
          }
          try {
            final notes = await _get('/repos/$repo/check-runs/${job['id']}/annotations') as List;
            for (final n in notes.take(10)) {
              out.writeln('  ${n['annotation_level']}: ${n['message']}');
            }
          } catch (_) {}
          try {
            final log = await _getText('/repos/$repo/actions/jobs/${job['id']}/logs');
            final lines = log.split('\n');
            final tail = lines.length > 120 ? lines.sublist(lines.length - 120) : lines;
            out.writeln('  End of log:');
            out.writeln(tail.join('\n'));
          } catch (e) {
            out.writeln('  (log not available: $e)');
          }
        }
        return clip(out.toString(), 20000);

      case 'github_create_issue':
        final repo = await _fullRepo(a['repo']);
        final j = await _send('POST', '/repos/$repo/issues', {'title': a['title'], 'body': a['body'] ?? ''}) as Map;
        return 'Created issue #${j['number']}: ${j['html_url']}';

      case 'github_comment':
        final repo = await _fullRepo(a['repo']);
        final j = await _send('POST', '/repos/$repo/issues/${a['number']}/comments', {'body': a['body']}) as Map;
        return 'Commented: ${j['html_url']}';

      case 'github_commit_file':
        final repo = await _fullRepo(a['repo']);
        final path = _path(a['path']);
        final branch = (a['branch'] ?? '').toString();
        String? sha;
        try {
          final existing = await _get('/repos/$repo/contents/$path${branch.isEmpty ? '' : '?ref=${_q(branch)}'}');
          if (existing is Map) sha = existing['sha']?.toString();
        } catch (_) {
          // New file.
        }
        final j = await _send('PUT', '/repos/$repo/contents/$path', {
          'message': a['message'],
          'content': base64Encode(utf8.encode((a['content'] ?? '').toString())),
          if (sha != null) 'sha': sha,
          if (branch.isNotEmpty) 'branch': branch,
        }) as Map;
        return 'Committed ${(j['commit']['sha'] as String).substring(0, 7)}: ${j['commit']['html_url']}';
    }
    throw Exception('Unknown GitHub tool $tool');
  }
}
