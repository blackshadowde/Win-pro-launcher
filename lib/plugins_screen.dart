import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'plugins/mcp.dart';
import 'theme.dart';

/// Turn plugins on, add tokens, and connect MCP servers.
class PluginsScreen extends StatefulWidget {
  final AppState app;
  const PluginsScreen({super.key, required this.app});

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  late final _ghToken = TextEditingController(text: widget.app.githubToken);
  bool _hideToken = true;
  String? _ghStatus;
  bool _ghTesting = false;
  final _refreshing = <McpServer>{};

  AppState get app => widget.app;

  @override
  void dispose() {
    _ghToken.dispose();
    super.dispose();
  }

  Future<void> _testGithub() async {
    await app.setGithub(token: _ghToken.text);
    setState(() {
      _ghTesting = true;
      _ghStatus = null;
    });
    try {
      final who = await app.github.whoAmI();
      _ghStatus = 'Signed in as $who';
    } catch (e) {
      _ghStatus = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _ghTesting = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Plugins', style: TextStyle(fontWeight: FontWeight.w700))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'Plugins let the AI read and act on your other apps. Anything that changes something '
              '(a commit, an issue, a comment) asks you first. You can turn plugins off per chat '
              'with the puzzle icon.',
              style: TextStyle(color: VibeColors.faint, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            _card(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: app.githubOn,
                  onChanged: (v) => app.setGithub(enabled: v),
                  secondary: const Icon(Icons.code, color: VibeColors.text),
                  title: const Text('GitHub', style: TextStyle(color: VibeColors.text, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Repos, files, issues, commits and Actions runs (why a build failed).',
                      style: TextStyle(color: VibeColors.faint, fontSize: 12.5)),
                ),
                TextField(
                  controller: _ghToken,
                  obscureText: _hideToken,
                  style: const TextStyle(color: VibeColors.text),
                  decoration: InputDecoration(
                    labelText: 'Access token',
                    hintText: 'github_pat_…',
                    filled: true,
                    fillColor: VibeColors.rail,
                    border: const OutlineInputBorder(borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: Icon(_hideToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: VibeColors.muted),
                      onPressed: () => setState(() => _hideToken = !_hideToken),
                    ),
                  ),
                  onSubmitted: (_) => _testGithub(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _ghTesting ? null : _testGithub,
                      child: Text(_ghTesting ? 'Checking…' : 'Save and check'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => launchUrl(Uri.parse('https://github.com/settings/tokens?type=beta'),
                          mode: LaunchMode.externalApplication),
                      child: const Text('Create a token'),
                    ),
                  ],
                ),
                if (_ghStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_ghStatus!, style: const TextStyle(color: VibeColors.muted, fontSize: 13)),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'Tip: a fine-grained token with read access to Contents, Issues, Actions and Metadata '
                  'is enough to read. Add write access to Contents and Issues to let it commit or open issues.',
                  style: TextStyle(color: VibeColors.faint, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _card(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: app.webOn,
                  onChanged: app.setWeb,
                  secondary: const Icon(Icons.public, color: VibeColors.text),
                  title: const Text('Web page reader',
                      style: TextStyle(color: VibeColors.text, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Opens links you mention and reads the page.',
                      style: TextStyle(color: VibeColors.faint, fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text('MCP servers',
                      style: TextStyle(color: VibeColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                TextButton.icon(
                  onPressed: _addMcp,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const Text(
              'Connect any MCP server that works over HTTP (Streamable HTTP). Its tools show up here.',
              style: TextStyle(color: VibeColors.faint, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            if (app.mcpServers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('None yet.', style: TextStyle(color: VibeColors.faint)),
              ),
            for (final m in app.mcpServers) ...[
              _card(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !m.enabled
                              ? VibeColors.faint
                              : m.connected
                                  ? VibeColors.online
                                  : VibeColors.danger,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.label,
                                style: const TextStyle(color: VibeColors.text, fontWeight: FontWeight.w600)),
                            Text(
                              _refreshing.contains(m)
                                  ? 'Connecting…'
                                  : m.connected
                                      ? '${m.toolCount} tools · ${m.url}'
                                      : (m.error ?? m.url),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: VibeColors.faint, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      Switch(value: m.enabled, onChanged: (v) => app.setMcpOn(m, v)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _refreshing.contains(m)
                            ? null
                            : () async {
                                setState(() => _refreshing.add(m));
                                await app.reconnectMcp(m);
                                if (mounted) setState(() => _refreshing.remove(m));
                              },
                        child: const Text('Refresh'),
                      ),
                      TextButton(
                        onPressed: () => _confirmRemove(m),
                        child: const Text('Remove', style: TextStyle(color: VibeColors.danger)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        decoration: BoxDecoration(color: VibeColors.card, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Future<void> _confirmRemove(McpServer m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibeColors.card,
        title: Text('Remove ${m.label}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await app.removeMcp(m);
  }

  Future<void> _addMcp() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final token = TextEditingController();
    InputDecoration deco(String label, [String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: VibeColors.rail,
          border: const OutlineInputBorder(borderSide: BorderSide.none),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibeColors.card,
        title: const Text('Add MCP server'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: deco('Name', 'e.g. Notes')),
              const SizedBox(height: 10),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: deco('Address', 'https://example.com/mcp'),
              ),
              const SizedBox(height: 10),
              TextField(controller: token, obscureText: true, decoration: deco('Token (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Connect')),
        ],
      ),
    );
    final u = url.text.trim();
    if (ok != true || u.isEmpty) return;
    final label = name.text.trim().isEmpty ? (Uri.tryParse(u)?.host ?? 'Server') : name.text.trim();
    final m = McpServer(label: label, url: u, token: token.text.trim());
    setState(() => _refreshing.add(m));
    await app.addMcp(m);
    if (mounted) setState(() => _refreshing.remove(m));
  }
}
