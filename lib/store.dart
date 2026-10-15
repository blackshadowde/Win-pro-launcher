import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class Msg {
  final String role; // user | assistant
  String text;
  /// provider/model that actually answered (from FreeLLMAPI's X-Routed-Via).
  String? via;
  bool error;
  final int at;

  Msg({required this.role, required this.text, this.via, this.error = false, int? at})
      : at = at ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {'r': role, 't': text, 'v': via, 'e': error, 'a': at};

  factory Msg.fromJson(Map<String, dynamic> j) => Msg(
        role: (j['r'] ?? 'user').toString(),
        text: (j['t'] ?? '').toString(),
        via: j['v'] as String?,
        error: j['e'] == true,
        at: j['a'] is int ? j['a'] as int : null,
      );
}

class Chat {
  final String id;
  /// Rail entry this chat lives under: a provider id, or `auto`.
  final String provider;
  String model;
  String title;
  final List<Msg> messages;
  int updated;

  Chat({
    required this.id,
    required this.provider,
    required this.model,
    this.title = '',
    List<Msg>? messages,
    int? updated,
  })  : messages = messages ?? [],
        updated = updated ?? DateTime.now().millisecondsSinceEpoch;

  String get preview {
    for (final m in messages.reversed) {
      if (m.text.trim().isNotEmpty) return m.text.replaceAll('\n', ' ').trim();
    }
    return 'No messages yet';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'p': provider,
        'm': model,
        't': title,
        'u': updated,
        'msgs': messages.map((m) => m.toJson()).toList(),
      };

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: j['id'].toString(),
        provider: (j['p'] ?? 'auto').toString(),
        model: (j['m'] ?? 'auto').toString(),
        title: (j['t'] ?? '').toString(),
        updated: j['u'] is int ? j['u'] as int : null,
        messages: (j['msgs'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Msg.fromJson)
            .toList(),
      );
}

/// All chats, saved as one JSON file in the app's private storage.
class ChatStore extends ChangeNotifier {
  final List<Chat> all = [];
  File? _file;
  Timer? _saveTimer;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/chats.json');
    try {
      if (await _file!.exists()) {
        final list = jsonDecode(await _file!.readAsString());
        if (list is List) {
          all
            ..clear()
            ..addAll(list.whereType<Map<String, dynamic>>().map(Chat.fromJson));
        }
      }
    } catch (_) {
      // A damaged file shouldn't stop the app; start fresh.
    }
  }

  List<Chat> forProvider(String provider) =>
      all.where((c) => c.provider == provider).toList()
        ..sort((a, b) => b.updated.compareTo(a.updated));

  Chat create(String provider, String model) {
    final c = Chat(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      provider: provider,
      model: model,
    );
    all.add(c);
    changed();
    return c;
  }

  void delete(Chat c) {
    all.removeWhere((x) => x.id == c.id);
    changed();
  }

  /// Call after editing a chat: notifies the UI and saves shortly after.
  void changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    // Empty chats nobody typed in aren't worth keeping.
    final keep = all.where((c) => c.messages.isNotEmpty).map((c) => c.toJson()).toList();
    await f.writeAsString(jsonEncode(keep));
  }
}
