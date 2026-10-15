import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'api.dart';
import 'app_state.dart';
import 'providers.dart';
import 'store.dart';
import 'theme.dart';
import 'ui/vibe_haptics.dart';

/// Vibe-style chat: slides over the home screen, drag back from anywhere.
class ChatScreen extends StatefulWidget {
  final AppState app;
  final Chat chat;
  const ChatScreen({super.key, required this.app, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<ChatChunk>? _sub;
  Msg? _streaming;

  Chat get chat => widget.chat;
  AppState get app => widget.app;
  bool get busy => _sub != null;

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || busy) return;
    VibeHaptics.light();
    _input.clear();

    chat.messages.add(Msg(role: 'user', text: text));
    if (chat.title.isEmpty) chat.title = text.length > 48 ? '${text.substring(0, 48)}…' : text;
    final history = chat.messages
        .where((m) => !m.error && m.text.trim().isNotEmpty)
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();

    final reply = Msg(role: 'assistant', text: '');
    chat.messages.add(reply);
    chat.updated = DateTime.now().millisecondsSinceEpoch;
    app.chats.changed();
    setState(() => _streaming = reply);

    _sub = app.api.chat(model: chat.model, messages: history).listen(
      (c) {
        if (c.via != null) reply.via = c.via;
        if (c.text != null) reply.text += c.text!;
        setState(() {});
      },
      onError: (Object e) {
        reply.error = true;
        reply.text = reply.text.isEmpty ? e.toString() : '${reply.text}\n\n_${e.toString()}_';
        _finish();
      },
      onDone: _finish,
      cancelOnError: true,
    );
  }

  void _finish() {
    final r = _streaming;
    if (r != null && r.text.trim().isEmpty && !r.error) {
      r.error = true;
      r.text = 'No reply. The model may be busy; try again or pick another model.';
    }
    _sub = null;
    _streaming = null;
    chat.updated = DateTime.now().millisecondsSinceEpoch;
    app.chats.changed();
    if (mounted) setState(() {});
  }

  void _stop() {
    _sub?.cancel();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final look = lookFor(chat.provider);
    final msgs = chat.messages;
    return Scaffold(
      backgroundColor: VibeColors.chat,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ProviderAvatar(id: chat.provider, size: 32, selected: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.title.isEmpty ? look.name : chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: VibeColors.text),
                  ),
                  Text(
                    app.modelName(chat.model),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: VibeColors.faint),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Change model',
            icon: const Icon(Icons.swap_horiz, color: VibeColors.muted),
            onPressed: _pickModel,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgs.isEmpty
                ? _EmptyChat(name: look.name, provider: chat.provider)
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemCount: msgs.length,
                    itemBuilder: (context, index) {
                      final i = msgs.length - 1 - index;
                      final m = msgs[i];
                      final header = i == 0 || msgs[i - 1].role != m.role;
                      return _MessageRow(
                        msg: m,
                        header: header,
                        provider: chat.provider,
                        typing: identical(m, _streaming) && m.text.isEmpty,
                      );
                    },
                  ),
          ),
          _Composer(
            controller: _input,
            hint: 'Message ${look.name}',
            busy: busy,
            onSend: _send,
            onStop: _stop,
          ),
        ],
      ),
    );
  }

  void _pickModel() {
    final models = app.modelsFor(chat.provider).where((m) => m.available).toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: VibeColors.card,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Model for this chat',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: VibeColors.text)),
            ),
            if (models.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No models are ready right now.', style: TextStyle(color: VibeColors.faint)),
              ),
            for (final m in models)
              ListTile(
                title: Text(m.name, style: const TextStyle(color: VibeColors.text)),
                subtitle: m.name != m.id ? Text(m.id, style: const TextStyle(color: VibeColors.faint)) : null,
                trailing: m.id == chat.model ? const Icon(Icons.check, color: VibeColors.blurple) : null,
                onTap: () {
                  setState(() => chat.model = m.id);
                  app.chats.changed();
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final String name;
  final String provider;
  const _EmptyChat({required this.name, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProviderAvatar(id: provider, size: 72, selected: true),
          const SizedBox(height: 14),
          Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: VibeColors.text)),
          const SizedBox(height: 6),
          Text(
            provider == 'auto'
                ? 'Every message goes to the best free model available right now.'
                : 'This is the beginning of your chat with $name.',
            style: const TextStyle(color: VibeColors.muted, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final Msg msg;
  final bool header;
  final String provider;
  final bool typing;
  const _MessageRow({required this.msg, required this.header, required this.provider, required this.typing});

  @override
  Widget build(BuildContext context) {
    final mine = msg.role == 'user';
    final via = msg.via;
    // Auto chats show the provider that actually answered.
    final answeredBy = !mine && via != null && via.contains('/') ? via.substring(0, via.indexOf('/')) : provider;
    final name = mine ? 'You' : lookFor(answeredBy).name;
    final time = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(msg.at)).format(context);

    final body = typing
        ? const Text('typing…', style: TextStyle(color: VibeColors.faint, fontStyle: FontStyle.italic))
        : msg.error
            ? Text(msg.text, style: const TextStyle(color: VibeColors.danger, fontSize: 14.5))
            : MarkdownBody(
                data: msg.text,
                selectable: true,
                styleSheet: _markdownStyle(context),
              );

    return GestureDetector(
      onLongPress: msg.text.isEmpty
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: msg.text));
              VibeHaptics.medium();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied'), behavior: SnackBarBehavior.floating),
              );
            },
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, header ? 14 : 2, 16, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: header
                  ? (mine
                      ? Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(color: VibeColors.blurple, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const Icon(Icons.person, color: Colors.white, size: 22),
                        )
                      : ProviderAvatar(id: answeredBy, size: 40, selected: true))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (header)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: VibeColors.text, fontWeight: FontWeight.w600, fontSize: 16)),
                          ),
                          const SizedBox(width: 8),
                          Text(time, style: const TextStyle(color: VibeColors.faint, fontSize: 12)),
                        ],
                      ),
                    ),
                  body,
                  if (!mine && via != null && !typing)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(viaLabel(via), style: const TextStyle(color: VibeColors.faint, fontSize: 11.5)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static MarkdownStyleSheet _markdownStyle(BuildContext context) {
    const base = TextStyle(color: VibeColors.text, fontSize: 15.5, height: 1.38);
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      listBullet: base,
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      h2: base.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      h3: base.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
      a: base.copyWith(color: const Color(0xFF00A8FC)),
      code: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13.5,
        color: VibeColors.text,
        backgroundColor: Color(0xFF2B2D31),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF111214),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.outline),
      ),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: VibeColors.outline, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  const _Composer({
    required this.controller,
    required this.hint,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(color: VibeColors.high, borderRadius: BorderRadius.circular(24)),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: VibeColors.text, fontSize: 16),
                  cursorColor: VibeColors.blurple,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: VibeColors.faint),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: busy ? VibeColors.highest : VibeColors.blurple),
                onPressed: busy ? onStop : onSend,
                icon: Icon(busy ? Icons.stop_rounded : Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
