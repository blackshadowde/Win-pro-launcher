import 'package:flutter/services.dart';

/// Node.js bundled inside the APK (built-in server, step 1: self-test).
class BuiltinNode {
  static const _ch = MethodChannel('vibe_ai/node');

  static Future<String> run(List<String> args) async =>
      (await _ch.invokeMethod<String>('run', {'args': args})) ?? 'No output';

  /// Checks the three things FreeLLMAPI needs: Node itself, its SQLite engine, and HTTPS.
  static Future<String> selfTest() => run([
        '-e',
        r'''
console.log('node: ' + process.version + ' (' + process.arch + ')');
try {
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(':memory:');
  db.exec('create table t(x)');
  db.prepare('insert into t values (?)').run(42);
  console.log('sqlite: ok (' + db.prepare('select x from t').get().x + ')');
} catch (e) { console.log('sqlite: FAIL ' + e.message); }
fetch('https://example.com')
  .then(r => console.log('https: ok (' + r.status + ')'))
  .catch(e => console.log('https: FAIL ' + (e.cause ? e.cause.message : e.message)));
''',
      ]);
}
