import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'builtin_node.dart';
import 'home.dart';
import 'providers.dart';
import 'termux.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  final AppState app;
  const SettingsScreen({super.key, required this.app});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _base = TextEditingController(text: widget.app.baseUrl);
  late final _dash = TextEditingController(text: widget.app.dashboardUrl);
  late final _key = TextEditingController(text: widget.app.apiKey);
  late final _folder = TextEditingController(text: widget.app.folder);
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signingIn = false;
  bool _checking = false;
  String? _savingStrategy;
  bool _showKey = false;
  bool _testingNode = false;
  String? _nodeResult;
  bool? _termuxInstalled;
  bool? _termuxAllowed;

  @override
  void initState() {
    super.initState();
    _checkTermux();
  }

  Future<void> _checkTermux() async {
    final installed = await Termux.installed();
    final allowed = installed && await Termux.hasPermission();
    if (mounted) {
      setState(() {
        _termuxInstalled = installed;
        _termuxAllowed = allowed;
      });
    }
  }

  @override
  void dispose() {
    _base.dispose();
    _dash.dispose();
    _key.dispose();
    _folder.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.app.saveSettings(
      baseUrl: _base.text,
      dashboardUrl: _dash.text,
      apiKey: _key.text,
      folder: _folder.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _install() async {
    if (_termuxInstalled != true) {
      _snack('Install Termux from F-Droid first.');
      return;
    }
    if (_termuxAllowed != true) {
      await Termux.requestPermission();
      await Future<void>.delayed(const Duration(seconds: 1));
      await _checkTermux();
      return;
    }
    try {
      // Foreground: opens a Termux session so you can watch the install.
      await Termux.run(Termux.installScript(widget.app.folder), background: false);
    } on PlatformException catch (e) {
      if (mounted) showAllowExternalAppsDialog(context, e.message);
    }
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      _snack('Enter the dashboard email and password.');
      return;
    }
    // Save the address first, so sign-in goes to the right server.
    await widget.app.saveSettings(
      baseUrl: _base.text,
      dashboardUrl: _dash.text,
      apiKey: _key.text,
      folder: _folder.text,
    );
    setState(() => _signingIn = true);
    try {
      await widget.app.signIn(_email.text, _password.text);
      _password.clear();
      _key.text = widget.app.apiKey;
      _snack('Signed in. The API key was filled in for you.');
    } catch (e) {
      _snack('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _setStrategy(String value) async {
    setState(() => _savingStrategy = value);
    try {
      await widget.app.setStrategy(value);
    } catch (e) {
      _snack('Could not change routing: $e');
    } finally {
      if (mounted) setState(() => _savingStrategy = null);
    }
  }

  Future<void> _checkKeys() async {
    setState(() => _checking = true);
    try {
      await widget.app.checkAllKeys();
      _snack('Keys checked.');
    } catch (e) {
      _snack('Check failed: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Header('SERVER'),
          _Field(label: 'API address', controller: _base, hint: 'http://127.0.0.1:3001'),
          _Field(
            label: 'Unified API key',
            controller: _key,
            hint: 'From the Keys page of the dashboard',
            obscure: !_showKey,
            suffix: IconButton(
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, color: VibeColors.faint),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
          _Field(label: 'Dashboard address', controller: _dash, hint: 'http://127.0.0.1:5173'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(_dash.text.trim()), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open dashboard (add provider keys, copy the unified key)'),
            ),
          ),
          const _Header('DASHBOARD'),
          ListenableBuilder(listenable: widget.app, builder: (context, _) => _dashboardSection()),
          const _Header('TERMUX'),
          _StatusLine(
            ok: _termuxInstalled,
            text: _termuxInstalled == null
                ? 'Checking Termux…'
                : _termuxInstalled!
                    ? 'Termux is installed'
                    : 'Termux is not installed (get it from F-Droid)',
          ),
          _StatusLine(
            ok: _termuxAllowed,
            text: _termuxAllowed == true
                ? 'Allowed to run commands in Termux'
                : 'Not yet allowed to run commands in Termux',
          ),
          if (_termuxInstalled == true && _termuxAllowed != true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await Termux.requestPermission();
                  await Future<void>.delayed(const Duration(seconds: 1));
                  await _checkTermux();
                },
                child: const Text('Allow running commands in Termux'),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Also needed once inside Termux, so it accepts commands from this app:',
            style: TextStyle(color: VibeColors.muted, fontSize: 13.5),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: VibeColors.rail, borderRadius: BorderRadius.circular(8)),
            child: const SelectableText(Termux.allowLine, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: Termux.allowLine));
                Termux.open();
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy and open Termux'),
            ),
          ),
          _Field(label: 'FreeLLMAPI folder in Termux home', controller: _folder, hint: 'freellmapi'),
          const SizedBox(height: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: VibeColors.blurple,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
            ),
            onPressed: _install,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Install FreeLLMAPI in Termux'),
          ),
          const SizedBox(height: 6),
          const Text(
            'Installs Node.js and git, downloads FreeLLMAPI and its packages. '
            'Opens Termux so you can watch; takes a few minutes the first time.',
            style: TextStyle(color: VibeColors.faint, fontSize: 12.5),
          ),
          const _Header('BUILT-IN SERVER (TEST)'),
          const Text(
            'Checks whether this app can run FreeLLMAPI by itself, without Termux: '
            'Node.js, its database engine and HTTPS.',
            style: TextStyle(color: VibeColors.muted, fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _testingNode
                ? null
                : () async {
                    setState(() {
                      _testingNode = true;
                      _nodeResult = null;
                    });
                    final out = await BuiltinNode.selfTest();
                    if (mounted) {
                      setState(() {
                        _testingNode = false;
                        _nodeResult = out;
                      });
                    }
                  },
            icon: _testingNode
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.terminal, size: 18),
            label: Text(_testingNode ? 'Testing…' : 'Test built-in Node'),
          ),
          if (_nodeResult != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: VibeColors.rail, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(_nodeResult!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: _nodeResult!)),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy result'),
              ),
            ),
          ],
          const _Header('KEEP IT RUNNING'),
          const Text(
            'Android can pause Termux with the screen off. Start keeps a wake lock while the server runs. '
            'Also set Battery to "Unrestricted" for Termux in Android settings.',
            style: TextStyle(color: VibeColors.muted, fontSize: 13.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}


extension _Dashboard on _SettingsScreenState {
  Widget _dashboardSection() {
    final app = widget.app;
    if (!app.signedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sign in with your FreeLLMAPI dashboard account to change routing, check keys, '
            'and fill in the API key automatically. Only a 30-day session is saved, not your password.',
            style: TextStyle(color: VibeColors.muted, fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          _Field(label: 'Dashboard email', controller: _email, hint: 'you@example.com'),
          _Field(label: 'Dashboard password', controller: _password, hint: '', obscure: true),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: VibeColors.blurple,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            onPressed: _signingIn ? null : _signIn,
            child: Text(_signingIn ? 'Signing in…' : 'Sign in'),
          ),
        ],
      );
    }

    const strategies = [
      ('balanced', 'Balanced', 'Reliability first, then speed and intelligence'),
      ('smartest', 'Smartest', 'Most capable model that still works'),
      ('fastest', 'Fastest', 'Quickest model that still works'),
      ('reliable', 'Most reliable', 'Highest success rate above all'),
      ('priority', 'Manual order', 'The order you set in the dashboard'),
    ];
    final current = app.strategy;
    final providers = app.keys.map((k) => k.provider).toSet().toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Signed in as ${app.dashEmail.isEmpty ? 'dashboard' : app.dashEmail}',
                  style: const TextStyle(color: VibeColors.muted)),
            ),
            TextButton(onPressed: app.signOut, child: const Text('Sign out')),
          ],
        ),
        if (app.dashError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(app.dashError!, style: const TextStyle(color: VibeColors.danger, fontSize: 13)),
          ),
        const SizedBox(height: 6),
        const Text('Routing for Auto', style: TextStyle(color: VibeColors.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (final (id, label, hint) in strategies)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _savingStrategy != null || id == current ? null : () => _setStrategy(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    id == current ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: id == current ? VibeColors.blurple : VibeColors.faint,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(color: VibeColors.text, fontSize: 15)),
                        Text(hint, style: const TextStyle(color: VibeColors.faint, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (_savingStrategy == id)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text('Provider keys', style: TextStyle(color: VibeColors.text, fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              onPressed: _checking ? null : _checkKeys,
              icon: _checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.health_and_safety_outlined, size: 18),
              label: Text(_checking ? 'Checking…' : 'Check all keys'),
            ),
          ],
        ),
        if (providers.isEmpty)
          const Text('No provider keys yet. Add them in the dashboard.',
              style: TextStyle(color: VibeColors.faint, fontSize: 13)),
        for (final p in providers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: healthColor(app.providerHealth(p)) ?? VibeColors.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lookFor(p).name, style: const TextStyle(color: VibeColors.text)),
                      if (app.providerHealth(p) != 'healthy' && app.providerError(p) != null)
                        Text(app.providerError(p)!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: VibeColors.faint, fontSize: 12)),
                    ],
                  ),
                ),
                Text(
                  switch (app.providerHealth(p)) {
                    'healthy' => 'OK',
                    'rate_limited' => 'Rate limited',
                    'problem' => 'Problem',
                    _ => 'Unchecked',
                  },
                  style: const TextStyle(color: VibeColors.faint, fontSize: 12.5),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(
          text,
          style: const TextStyle(
            color: VibeColors.faint,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffix;
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(color: VibeColors.text),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: VibeColors.rail,
          suffixIcon: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final bool? ok;
  final String text;
  const _StatusLine({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok == null ? Icons.more_horiz : (ok! ? Icons.check_circle : Icons.cancel),
            size: 18,
            color: ok == true ? VibeColors.online : VibeColors.faint,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: VibeColors.muted))),
        ],
      ),
    );
  }
}
