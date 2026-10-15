import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'server.dart';
import 'theme.dart';

/// Live output of the built-in server, terminal style.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _lines = <String>[];
  final _scroll = ScrollController();
  Timer? _timer;
  int _total = 0;
  String _state = 'stopped';
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // Follow new lines only while you're at the bottom.
      if (!_scroll.hasClients) return;
      final atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
      if (atBottom != _follow) setState(() => _follow = atBottom);
    });
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final snap = await BuiltinServer.snapshot(_total);
      if (!mounted) return;
      final grew = snap.lines.isNotEmpty;
      setState(() {
        _lines.addAll(snap.lines);
        if (_lines.length > 3000) _lines.removeRange(0, _lines.length - 3000);
        _total = snap.total;
        _state = snap.state;
      });
      if (grew && _follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (_state) {
      'running' => (VibeColors.online, 'Running'),
      'preparing' => (VibeColors.idle, 'Starting'),
      'exited' => (VibeColors.danger, 'Stopped with an error'),
      _ => (VibeColors.faint, 'Stopped'),
    };
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0D),
        title: Row(
          children: [
            const Text('Server logs', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: VibeColors.faint, fontSize: 13)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy, color: VibeColors.muted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _lines.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied'), behavior: SnackBarBehavior.floating),
              );
            },
          ),
          IconButton(
            tooltip: 'Clear view',
            icon: const Icon(Icons.delete_sweep_outlined, color: VibeColors.muted),
            onPressed: () => setState(_lines.clear),
          ),
        ],
      ),
      body: _lines.isEmpty
          ? const Center(
              child: Text('No output yet. Start the server to see its logs here.',
                  style: TextStyle(color: VibeColors.faint)),
            )
          : Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _lines.length,
                itemBuilder: (context, i) {
                  final line = _lines[i];
                  final lower = line.toLowerCase();
                  final c = lower.contains('error') || lower.contains('fail')
                      ? const Color(0xFFFF7A7A)
                      : lower.contains('warn')
                          ? const Color(0xFFF0C674)
                          : const Color(0xFFD7DAE0);
                  return SelectableText(
                    line,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35, color: c),
                  );
                },
              ),
            ),
      floatingActionButton: _follow
          ? null
          : FloatingActionButton.small(
              backgroundColor: VibeColors.blurple,
              onPressed: () {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
                setState(() => _follow = true);
              },
              child: const Icon(Icons.arrow_downward, color: Colors.white),
            ),
    );
  }
}
