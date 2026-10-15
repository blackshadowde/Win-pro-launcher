import 'package:flutter/services.dart';

/// Talks to Termux through the Android side (MainActivity.kt).
class Termux {
  static const _ch = MethodChannel('vibe_ai/termux');

  static Future<bool> installed() async => (await _ch.invokeMethod<bool>('installed')) ?? false;

  static Future<bool> hasPermission() async =>
      (await _ch.invokeMethod<bool>('hasPermission')) ?? false;

  static Future<void> requestPermission() => _ch.invokeMethod('requestPermission');

  static Future<void> open() => _ch.invokeMethod('openTermux');

  /// Runs [script] with bash in Termux. Foreground runs open a Termux session you can watch.
  static Future<void> run(String script, {bool background = true}) =>
      _ch.invokeMethod('run', {'script': script, 'background': background});

  /// One-time line to paste into Termux so other apps may run commands there.
  static const allowLine =
      'mkdir -p ~/.termux && echo "allow-external-apps=true" >> ~/.termux/termux.properties && termux-reload-settings';

  static String installScript(String folder) =>
      'pkg install -y nodejs-lts git termux-api; '
      '(test -d ~/$folder || git clone https://github.com/tashfeenahmed/freellmapi.git ~/$folder) && '
      'cd ~/$folder && npm install --no-audit --no-fund && '
      'echo && echo "Done. Go back to Vibe AI and tap Start."';

  static String startScript(String folder) =>
      'cd ~/$folder && (termux-wake-lock 2>/dev/null || true); '
      'nohup npm run dev > ~/$folder/vibe-ai.log 2>&1 &';

  static String stopScript(String folder) =>
      'pkill -f "/$folder/"; (termux-wake-unlock 2>/dev/null || true); true';
}
