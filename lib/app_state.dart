import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'server.dart';
import 'store.dart';

enum ServerStatus { checking, running, stopped, needsKey, error }

/// Settings, the live model list and server status, plus saved chats.
class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;

  String baseUrl = 'http://127.0.0.1:3001';
  String dashboardUrl = 'http://127.0.0.1:5173';
  String apiKey = '';
  String folder = 'freellmapi';

  /// `builtin` = FreeLLMAPI runs inside this app; `termux` = it runs in Termux.
  String serverMode = 'builtin';
  /// Built-in server process: stopped | preparing | running | exited.
  String serverState = 'stopped';
  bool get builtin => serverMode == 'builtin';

  /// Where the dashboard is: the built-in server serves it on its own port.
  String get dashboardLink => builtin ? baseUrl : dashboardUrl;

  /// Dashboard session (30 days). Only the token is kept, never the password.
  String dashToken = '';
  String dashEmail = '';
  Map<String, dynamic> routing = const {};
  List<KeyHealth> keys = const [];
  String? dashError;
  int _pollCount = 0;

  List<ModelInfo> models = const [];
  ServerStatus status = ServerStatus.checking;
  String? lastError;

  final ChatStore chats = ChatStore();
  Timer? _poll;
  bool _refreshing = false;

  LlmApi get api => LlmApi(baseUrl, apiKey);
  DashboardApi get dash => DashboardApi(baseUrl, dashToken);
  bool get signedIn => dashToken.isNotEmpty;
  String get strategy => (routing['strategy'] ?? '').toString();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs.getString('baseUrl') ?? baseUrl;
    dashboardUrl = _prefs.getString('dashboardUrl') ?? dashboardUrl;
    apiKey = _prefs.getString('apiKey') ?? apiKey;
    folder = _prefs.getString('folder') ?? folder;
    serverMode = _prefs.getString('serverMode') ?? serverMode;
    dashToken = _prefs.getString('dashToken') ?? '';
    dashEmail = _prefs.getString('dashEmail') ?? '';
    await chats.load();
    unawaited(refresh());
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => refresh());
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String dashboardUrl,
    required String apiKey,
    required String folder,
  }) async {
    this.baseUrl = baseUrl.trim().isEmpty ? 'http://127.0.0.1:3001' : baseUrl.trim();
    this.dashboardUrl = dashboardUrl.trim().isEmpty ? 'http://127.0.0.1:5173' : dashboardUrl.trim();
    this.apiKey = apiKey.trim();
    this.folder = folder.trim().isEmpty ? 'freellmapi' : folder.trim();
    await _prefs.setString('baseUrl', this.baseUrl);
    await _prefs.setString('dashboardUrl', this.dashboardUrl);
    await _prefs.setString('apiKey', this.apiKey);
    await _prefs.setString('folder', this.folder);
    status = ServerStatus.checking;
    notifyListeners();
    await refresh();
  }

  /// Polls /v1/models: tells us if the server is up and which models can answer.
  Future<void> setServerMode(String mode) async {
    serverMode = mode;
    await _prefs.setString('serverMode', mode);
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (builtin) {
      try {
        serverState = (await BuiltinServer.snapshot(1 << 30)).state;
      } catch (_) {}
    }
    try {
      models = await api.models();
      status = ServerStatus.running;
      lastError = null;
      // Key health is cheaper to check less often than the model list.
      if (signedIn && (_pollCount++ % 5 == 0 || keys.isEmpty)) unawaited(loadDashboard());
    } on ApiException catch (e) {
      status = e.status == 401 || e.status == 403 ? ServerStatus.needsKey : ServerStatus.error;
      lastError = e.message;
    } catch (_) {
      if (builtin && (serverState == 'preparing' || serverState == 'running')) {
        status = ServerStatus.checking; // still starting up
        lastError = null;
      } else if (builtin && serverState == 'exited') {
        status = ServerStatus.error;
        lastError = 'The built-in server stopped unexpectedly. Open Logs to see why.';
      } else {
        status = ServerStatus.stopped;
        lastError = null;
      }
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  void markStarting() {
    status = ServerStatus.checking;
    notifyListeners();
  }

  // ---- Dashboard ------------------------------------------------------------------------

  /// Signs in to the dashboard, then fetches the unified API key automatically.
  Future<void> signIn(String email, String password) async {
    final token = await DashboardApi.login(baseUrl, email, password);
    dashToken = token;
    dashEmail = email.trim();
    await _prefs.setString('dashToken', dashToken);
    await _prefs.setString('dashEmail', dashEmail);
    final key = await dash.unifiedKey();
    if (key != null && key.isNotEmpty) {
      apiKey = key;
      await _prefs.setString('apiKey', apiKey);
    }
    notifyListeners();
    await refresh();
    await loadDashboard();
  }

  Future<void> signOut() async {
    dashToken = '';
    dashEmail = '';
    routing = const {};
    keys = const [];
    await _prefs.remove('dashToken');
    await _prefs.remove('dashEmail');
    notifyListeners();
  }

  Future<void> loadDashboard() async {
    if (!signedIn) return;
    try {
      routing = await dash.routing();
      keys = await dash.keys();
      dashError = null;
    } on ApiException catch (e) {
      dashError = e.message;
      if (e.status == 401) await signOut();
    } catch (_) {
      dashError = 'Could not reach the dashboard API.';
    }
    notifyListeners();
  }

  Future<void> setStrategy(String value) async {
    await dash.setStrategy(value, routing);
    await loadDashboard();
  }

  Future<void> checkAllKeys() async {
    await dash.checkAllKeys();
    await loadDashboard();
    await refresh();
  }

  /// Best status among a provider's keys: healthy > rate_limited > problem. Null = unknown.
  String? providerHealth(String provider) {
    final mine = keys.where((k) => k.provider == provider && k.enabled).toList();
    if (mine.isEmpty) return null;
    if (mine.any((k) => k.status == 'healthy')) return 'healthy';
    if (mine.any((k) => k.status == 'rate_limited')) return 'rate_limited';
    if (mine.any((k) => k.status == 'invalid' || k.status == 'error')) return 'problem';
    return null;
  }

  String? providerError(String provider) {
    for (final k in keys) {
      if (k.provider == provider && k.error != null && k.error!.isNotEmpty) return k.error;
    }
    return null;
  }

  /// Providers that have at least one model ready right now, for the rail.
  List<String> get providers {
    final set = <String>{};
    for (final m in models) {
      if (m.available && m.provider != 'freellmapi' && m.provider != 'unknown') set.add(m.provider);
    }
    final list = set.toList()..sort();
    return list;
  }

  int get readyCount => models.where((m) => m.available && !m.isRouter).length;

  /// Models listed under a rail entry. `auto` = the router's own entries.
  List<ModelInfo> modelsFor(String provider) {
    if (provider == 'fusion') {
      return const [ModelInfo(id: 'fusion', name: 'Fusion', provider: 'freellmapi', available: true)];
    }
    if (provider == 'auto') {
      final routers = models.where((m) => m.isAutoChain).toList();
      if (!routers.any((m) => m.id == 'auto')) {
        routers.insert(0, const ModelInfo(id: 'auto', name: 'Auto', provider: 'freellmapi', available: true));
      }
      return routers;
    }
    final list = models.where((m) => m.provider == provider).toList()
      ..sort((a, b) {
        if (a.available != b.available) return a.available ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  /// Model used when you tap "New chat" under a rail entry.
  String defaultModelFor(String provider) {
    if (provider == 'auto') return 'auto';
    if (provider == 'fusion') return 'fusion';
    final list = modelsFor(provider);
    final ready = list.where((m) => m.available);
    if (ready.isNotEmpty) return ready.first.id;
    return list.isNotEmpty ? list.first.id : 'auto';
  }

  String modelName(String id) {
    for (final m in models) {
      if (m.id == id) return m.name;
    }
    if (id == 'auto') return 'Auto';
    if (id == 'fusion') return 'Fusion';
    return id;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
