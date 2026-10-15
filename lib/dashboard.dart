import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_state.dart';
import 'theme.dart';

/// FreeLLMAPI's dashboard inside the app. If you're signed in under Settings,
/// the same session is handed to the dashboard so you don't log in twice.
class DashboardScreen extends StatefulWidget {
  final AppState app;
  final String path;
  const DashboardScreen({super.key, required this.app, this.path = '/'});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final WebViewController _web;
  int _progress = 0;
  bool _sessionHandedOver = false;
  String? _error;

  String get _root {
    final u = widget.app.dashboardLink;
    return u.endsWith('/') ? u.substring(0, u.length - 1) : u;
  }

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(VibeColors.chat)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageFinished: (_) => _handOverSession(),
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() => _error = 'Could not open the dashboard. Is the server running?\n${e.description}');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('$_root${widget.path}'));
  }

  /// Puts the app's dashboard session into the page's storage once, then reloads.
  Future<void> _handOverSession() async {
    final token = widget.app.dashToken;
    if (token.isEmpty) {
      await _pickUpSession();
      return;
    }
    if (_sessionHandedOver) return;
    _sessionHandedOver = true;
    try {
      final has = await _web.runJavaScriptReturningResult(
        "localStorage.getItem('freellmapi_dashboard_token') ? 'yes' : 'no'",
      );
      if (has.toString().contains('yes')) return;
      await _web.runJavaScript("localStorage.setItem('freellmapi_dashboard_token', ${jsonEncode(token)});");
      await _web.reload();
    } catch (_) {
      // Not fatal: you can still sign in on the page itself.
    }
  }

  /// If you sign up or log in on the page, the app uses that session too.
  Future<void> _pickUpSession() async {
    try {
      final r = await _web.runJavaScriptReturningResult(
        "localStorage.getItem('freellmapi_dashboard_token') || ''",
      );
      var t = r.toString();
      if (t.startsWith('"') && t.endsWith('"')) t = jsonDecode(t) as String;
      if (t.isNotEmpty && t != 'null') await widget.app.adoptDashToken(t);
    } catch (_) {}
  }

  @override
  void dispose() {
    // The page is a single-page app, so login may not trigger a page load: check once more.
    if (widget.app.dashToken.isEmpty) _pickUpSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh, color: VibeColors.muted),
              onPressed: () {
                setState(() => _error = null);
                _web.reload();
              },
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 2,
                    color: VibeColors.blurple,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : null,
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: VibeColors.muted)),
                ),
              )
            : WebViewWidget(controller: _web),
      ),
    );
  }
}
