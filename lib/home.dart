import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'app_state.dart';
import 'chat.dart';
import 'dashboard.dart';
import 'logs.dart';
import 'server.dart';
import 'providers.dart';
import 'settings.dart';
import 'store.dart';
import 'termux.dart';
import 'theme.dart';
import 'ui/vibe_haptics.dart';
import 'ui/vibe_motion.dart';

/// Discord layout: provider rail on the left, chats + models in the pane, user bar at the bottom.
class HomeScreen extends StatefulWidget {
  final AppState app;
  const HomeScreen({super.key, required this.app});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selected = 'auto';

  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.chats]),
      builder: (context, _) {
        final providers = app.providers;
        final selected =
            (_selected == 'auto' ||
                    _selected == 'fusion' ||
                    providers.contains(_selected) ||
                    app.chats.forProvider(_selected).isNotEmpty)
                ? _selected
                : 'auto';
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: VibeColors.card,
          ),
          child: Scaffold(
            backgroundColor: VibeColors.rail,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _Rail(
                          providers: providers,
                          health: {for (final p in providers) p: app.providerHealth(p)},
                          selected: selected,
                          onSelect: (p) {
                            VibeHaptics.selection();
                            setState(() => _selected = p);
                          },
                          onAdd: _openDashboard,
                          onSettings: _openSettings,
                        ),
                        Expanded(child: _Pane(app: app, provider: selected, onStart: _startServer)),
                      ],
                    ),
                  ),
                  _UserBar(
                    app: app,
                    onStart: _startServer,
                    onStop: _stopServer,
                    onSettings: _openSettings,
                    onLogs: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogsScreen())),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(app: app)));
  }

  void _openDashboard() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DashboardScreen(app: app)));
  }

  Future<void> _startServer() async {
    if (app.builtin) {
      try {
        await BuiltinServer.start();
        app.markStarting();
        _snack('Starting the built-in server… the first start unpacks it and can take a minute.');
      } on PlatformException catch (e) {
        _snack('Could not start: ${e.message}');
      }
      return;
    }
    if (!await _termuxReady()) return;
    try {
      await Termux.run(Termux.startScript(app.folder));
      app.markStarting();
      _snack('Starting FreeLLMAPI… the first start can take up to a minute.');
    } on PlatformException catch (e) {
      _showAllowDialog(e.message);
    }
  }

  Future<void> _stopServer() async {
    if (app.builtin) {
      await BuiltinServer.stop();
      _snack('Stopping the server…');
      Future.delayed(const Duration(seconds: 2), app.refresh);
      return;
    }
    if (!await _termuxReady()) return;
    try {
      await Termux.run(Termux.stopScript(app.folder));
      _snack('Stopping FreeLLMAPI…');
      Future.delayed(const Duration(seconds: 2), app.refresh);
    } on PlatformException catch (e) {
      _showAllowDialog(e.message);
    }
  }

  Future<bool> _termuxReady() async {
    if (!await Termux.installed()) {
      _snack('Termux is not installed. Get it from F-Droid.');
      return false;
    }
    if (!await Termux.hasPermission()) {
      await Termux.requestPermission();
      _snack('Allow "Run commands in Termux", then tap again.');
      return false;
    }
    return true;
  }

  void _showAllowDialog(String? error) {
    showAllowExternalAppsDialog(context, error);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }
}

/// Explains the one-time Termux setting with a copy button.
void showAllowExternalAppsDialog(BuildContext context, String? error) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: VibeColors.card,
      title: const Text('One-time Termux setup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Termux only accepts commands from other apps once you allow it. '
              'Open Termux, paste this line and press enter:'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: VibeColors.rail, borderRadius: BorderRadius.circular(8)),
            child: const SelectableText(Termux.allowLine, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error, style: const TextStyle(color: VibeColors.faint, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: Termux.allowLine));
            Termux.open();
            Navigator.pop(ctx);
          },
          child: const Text('Copy & open Termux'),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------------------------
// Rail

class _Rail extends StatelessWidget {
  final List<String> providers;
  final Map<String, String?> health;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onSettings;

  const _Rail({
    required this.providers,
    required this.health,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _RailItem(id: 'auto', selected: selected == 'auto', onTap: () => onSelect('auto')),
                _RailItem(id: 'fusion', selected: selected == 'fusion', onTap: () => onSelect('fusion')),
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    width: 32,
                    height: 2,
                    decoration: BoxDecoration(color: VibeColors.outline, borderRadius: BorderRadius.circular(1)),
                  ),
                ),
                for (final p in providers)
                  _RailItem(id: p, selected: selected == p, health: health[p], onTap: () => onSelect(p)),
                const SizedBox(height: 4),
                _RailButton(icon: Icons.add, tooltip: 'Add provider keys', onTap: onAdd),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RailButton(icon: Icons.settings_outlined, tooltip: 'Settings', onTap: onSettings),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final String id;
  final bool selected;
  final String? health;
  final VoidCallback onTap;
  const _RailItem({required this.id, required this.selected, required this.onTap, this.health});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Discord's selection pill on the left edge.
            Positioned(
              left: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 4,
                height: selected ? 40 : 0,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
            ),
            Tooltip(
              message: lookFor(id).name,
              child: VibePressable(
                child: GestureDetector(
                  onTap: onTap,
                  child: ProviderAvatar(id: id, selected: selected),
                ),
              ),
            ),
            // Key health dot (green ok, yellow rate limited, red problem).
            if (healthColor(health) != null)
              Positioned(
                right: 10,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: healthColor(health),
                      shape: BoxShape.circle,
                      border: Border.all(color: VibeColors.rail, width: 3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RailButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Tooltip(
          message: tooltip,
          child: VibePressable(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: VibeColors.highest, shape: BoxShape.circle),
                child: Icon(icon, color: VibeColors.online, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Pane: chats and models of the selected rail entry

class _Pane extends StatelessWidget {
  final AppState app;
  final String provider;
  final VoidCallback onStart;
  const _Pane({required this.app, required this.provider, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final look = lookFor(provider);
    final chats = app.chats.forProvider(provider);
    final models = app.modelsFor(provider);
    final ready = models.where((m) => m.available).length;
    final running = app.status == ServerStatus.running;

    return Container(
      decoration: const BoxDecoration(
        color: VibeColors.pane,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Text(
              look.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: VibeColors.text),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              switch (provider) {
                'auto' => 'Picks the best free model for every message'
                    '${app.strategy.isEmpty ? '' : ' · ${strategyLabel(app.strategy)}'}',
                'fusion' => 'Several models answer at once, then one blended answer',
                _ => '$ready of ${models.length} models ready${_healthText(app, provider)}',
              },
              style: const TextStyle(fontSize: 13, color: VibeColors.faint),
            ),
          ),
          const Divider(height: 1, color: VibeColors.outline),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
              children: [
                if (!running) _SetupCard(app: app, onStart: onStart),
                if (running && !app.signedIn && provider == 'auto')
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Text(
                      'To see each provider (Groq, OpenRouter…) in the rail, open the dashboard once '
                      'and log in, or sign in under Settings → Dashboard.',
                      style: TextStyle(color: VibeColors.faint, fontSize: 13),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: VibeColors.blurple,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    onPressed: () => _newChat(context, app.defaultModelFor(provider)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('New chat', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const _SectionLabel('CHATS'),
                if (chats.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 2, 12, 8),
                    child: Text('No chats yet.', style: TextStyle(color: VibeColors.faint, fontSize: 13)),
                  ),
                for (var i = 0; i < chats.length; i++)
                  VibeStagger(
                    key: ValueKey('chat_${chats[i].id}'),
                    index: i,
                    child: _ChatRow(app: app, chat: chats[i]),
                  ),
                if (models.isNotEmpty) _SectionLabel(provider == 'auto' ? 'ROUTERS' : 'MODELS'),
                for (final m in models) _ModelRow(model: m, onTap: () => _newChat(context, m.id)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _newChat(BuildContext context, String model) {
    VibeHaptics.light();
    final chat = app.chats.create(provider, model);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(app: app, chat: chat)));
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
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

class _ChatRow extends StatelessWidget {
  final AppState app;
  final Chat chat;
  const _ChatRow({required this.app, required this.chat});

  @override
  Widget build(BuildContext context) {
    return VibePressable(
      scale: 0.98,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(app: app, chat: chat)),
        ),
        onLongPress: () => _confirmDelete(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              ProviderAvatar(id: chat.provider, size: 38, selected: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.title.isEmpty ? 'New chat' : chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: VibeColors.text, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chat.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: VibeColors.faint, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    VibeHaptics.medium();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibeColors.card,
        title: const Text('Delete chat?'),
        content: Text(chat.title.isEmpty ? 'This chat will be removed.' : '"${chat.title}" will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              app.chats.delete(chat);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: VibeColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  final ModelInfo model;
  final VoidCallback onTap;
  const _ModelRow({required this.model, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: model.available ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: model.available ? VibeColors.online : VibeColors.outline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                model.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: model.available ? VibeColors.muted : VibeColors.faint,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in the pane until the server answers.
class _SetupCard extends StatelessWidget {
  final AppState app;
  final VoidCallback onStart;
  const _SetupCard({required this.app, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final needsKey = app.status == ServerStatus.needsKey;
    final title = switch (app.status) {
      ServerStatus.checking => 'Connecting to FreeLLMAPI…',
      ServerStatus.needsKey => 'Add your API key',
      ServerStatus.error => 'FreeLLMAPI had a problem',
      _ => 'FreeLLMAPI isn\'t running',
    };
    final body = switch (app.status) {
      ServerStatus.checking => app.builtin
          ? 'Starting the built-in server. The first start unpacks it and can take a minute.'
          : 'Looking for the server at ${app.baseUrl}.',
      ServerStatus.needsKey => app.builtin
          ? 'Open the dashboard (+ in the rail), create your account and add provider keys. '
              'Then sign in under Settings → Dashboard.'
          : 'Open the dashboard, copy the unified key from the Keys page, and paste it in Settings.',
      ServerStatus.error => app.lastError ?? (app.builtin ? 'Open Logs to see what happened.' : 'Check Termux for errors.'),
      _ => app.builtin
          ? 'Tap Start. The server runs inside this app, no Termux needed.'
          : 'Start it in Termux from here. First time? Use "Install in Termux" in Settings.',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: VibeColors.card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: VibeColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: VibeColors.muted, fontSize: 13.5, height: 1.35)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!needsKey && app.status != ServerStatus.checking)
                OutlinedButton(onPressed: onStart, child: const Text('Start server')),
              OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => SettingsScreen(app: app))),
                child: const Text('Settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// User bar

class _UserBar extends StatelessWidget {
  final AppState app;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onSettings;
  final VoidCallback onLogs;
  const _UserBar({
    required this.app,
    required this.onStart,
    required this.onStop,
    required this.onSettings,
    required this.onLogs,
  });

  @override
  Widget build(BuildContext context) {
    final (dot, line) = switch (app.status) {
      ServerStatus.running => (VibeColors.online, 'Running · ${app.readyCount} models ready'),
      ServerStatus.checking => (VibeColors.idle, app.builtin ? 'Starting…' : 'Connecting…'),
      ServerStatus.needsKey => (VibeColors.idle, 'Needs your API key'),
      ServerStatus.error => (VibeColors.danger, 'Error · tap Settings'),
      ServerStatus.stopped => (VibeColors.faint, 'Not running'),
    };
    final running = app.status == ServerStatus.running ||
        (app.builtin && (app.serverState == 'running' || app.serverState == 'preparing'));
    return Container(
      color: VibeColors.card,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(color: VibeColors.highest, shape: BoxShape.circle),
                    child: const Icon(Icons.dns_outlined, size: 18, color: VibeColors.muted),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: VibeColors.card, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('FreeLLMAPI',
                        style: TextStyle(color: VibeColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: VibeColors.faint, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(
                tooltip: running ? 'Stop server' : 'Start server',
                onPressed: running ? onStop : onStart,
                icon: Icon(running ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                    color: VibeColors.muted),
              ),
              if (app.builtin)
                IconButton(
                  tooltip: 'Server logs',
                  onPressed: onLogs,
                  icon: const Icon(Icons.terminal, color: VibeColors.muted),
                ),
              IconButton(
                tooltip: 'Settings',
                onPressed: onSettings,
                icon: const Icon(Icons.settings_outlined, color: VibeColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _healthText(AppState app, String provider) => switch (app.providerHealth(provider)) {
      'healthy' => ' · key OK',
      'rate_limited' => ' · rate limited',
      'problem' => ' · key problem',
      _ => '',
    };

/// Display names for FreeLLMAPI routing strategies.
String strategyLabel(String s) => switch (s) {
      'priority' => 'Manual order',
      'balanced' => 'Balanced',
      'smartest' => 'Smartest',
      'fastest' => 'Fastest',
      'reliable' => 'Most reliable',
      'custom' => 'Custom weights',
      _ => s,
    };
