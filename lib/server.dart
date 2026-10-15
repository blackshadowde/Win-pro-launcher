import 'package:flutter/services.dart';

/// The FreeLLMAPI server built into the app (Android ServerService).
class BuiltinServer {
  static const _ch = MethodChannel('vibe_ai/server');

  static Future<void> start() => _ch.invokeMethod('start');
  static Future<void> stop() => _ch.invokeMethod('stop');

  /// Log lines numbered from [from], plus the total count and state
  /// (stopped | preparing | running | exited).
  static Future<ServerSnapshot> snapshot(int from) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('snapshot', {'from': from}) ?? {};
    return ServerSnapshot(
      total: (m['total'] as int?) ?? 0,
      lines: (m['lines'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      state: (m['state'] as String?) ?? 'stopped',
    );
  }

  static Future<bool> batteryUnrestricted() async =>
      (await _ch.invokeMethod<bool>('batteryUnrestricted')) ?? false;

  static Future<void> openBatterySettings() => _ch.invokeMethod('openBatterySettings');
}

class ServerSnapshot {
  final int total;
  final List<String> lines;
  final String state;
  const ServerSnapshot({required this.total, required this.lines, required this.state});
}
