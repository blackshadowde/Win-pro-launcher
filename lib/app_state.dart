import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'store.dart';

enum ServerStatus { checking, running, stopped, needsKey, error }

/// Settings, the live model list and server status, plus saved chats.
class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;

  String baseUrl = 'http://127.0.0.1:3001';
  String dashboardUrl = 'http://127.0.0.1:5173';
  String apiKey = '';
  String folder = 'freellmapi';

  List<ModelInfo> models = const [];
  ServerStatus status = ServerStatus.checking;
  String? lastError;

  final ChatStore chats = ChatStore();
  Timer? _poll;
  bool _refreshing = false;

  LlmApi get api => LlmApi(baseUrl, apiKey);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs.getString('baseUrl') ?? baseUrl;
    dashboardUrl = _prefs.getString('dashboardUrl') ?? dashboardUrl;
    apiKey = _prefs.getString('apiKey') ?? apiKey;
    folder = _prefs.getString('folder') ?? folder;
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
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      models = await api.models();
      status = ServerStatus.running;
      lastError = null;
    } on ApiException catch (e) {
      status = e.status == 401 || e.status == 403 ? ServerStatus.needsKey : ServerStatus.error;
      lastError = e.message;
    } catch (_) {
      status = ServerStatus.stopped;
      lastError = null;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  void markStarting() {
    status = ServerStatus.checking;
    notifyListeners();
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
    if (provider == 'auto') {
      final routers = models.where((m) => m.isRouter).toList();
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
    final list = modelsFor(provider);
    final ready = list.where((m) => m.available);
    if (ready.isNotEmpty) return ready.first.id;
    return list.isNotEmpty ? list.first.id : 'auto';
  }

  String modelName(String id) {
    for (final m in models) {
      if (m.id == id) return m.name;
    }
    return id == 'auto' ? 'Auto' : id;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
