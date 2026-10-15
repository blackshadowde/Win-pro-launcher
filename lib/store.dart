import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class Msg {
  final String role; // user | assistant
  String text;
  /// provider/model that actually answered (from FreeLLMAPI's X-Routed-Via).
  String? via;
  bool error;
  final int at;
  /// Generated images, saved as files in the app's private storage.
  final List<String> images;

  Msg({required this.role, required this.text, this.via, this.error = false, int? at, List<String>? images})
      : at = at ?? DateTime.now().millisecondsSinceEpoch,
        images = images ?? [];

  Map<String, dynamic> toJson() => {
        'r': role,
        't': text,
        'v': via,
        'e': error,
        'a': at,
        if (images.isNotEmpty) 'i': images,
      };

  factory Msg.fromJson(Map<String, dynamic> j) => Msg(
        role: (j['r'] ?? 'user').toString(),
        text: (j['t'] ?? '').toString(),
        via: j['v'] as String?,
        error: j['e'] == true,
        at: j['a'] is int ? j['a'] as int : null,
        images: (j['i'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

class Chat {
  final String id;
  /// Rail entry this chat lives under: a provider id, or `auto`.
  final String provider;
  String model;
  String title;
  /// Instructions sent before every message in this chat (optional).
  String system;
  final List<Msg> messages;
  int updated;

  Chat({
    required this.id,
    required this.provider,
    required this.model,
    this.title = '',
    this.system = '',
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
        's': system,
        'u': updated,
        'msgs': messages.map((m) => m.toJson()).toList(),
      };

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: j['id'].toString(),
        provider: (j['p'] ?? 'auto').toString(),
        model: (j['m'] ?? 'auto').toString(),
        title: (j['t'] ?? '').toString(),
        system: (j['s'] ?? '').toString(),
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
    for (final m in c.messages) {
      for (final path in m.images) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }
    all.removeWhere((x) => x.id == c.id);
    changed();
  }

  /// Saves a generated image and returns its file path.
  Future<String> saveImage(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/images');
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File('${folder.path}/${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file.path;
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
    final keep = all.where((c) => c.messages.isNotEmpty || c.system.isNotEmpty).map((c) => c.toJson()).toList();
    await f.writeAsString(jsonEncode(keep));
  }
}
