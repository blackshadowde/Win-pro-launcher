import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
  final _speech = SpeechToText();
  StreamSubscription<ChatChunk>? _sub;
  Msg? _streaming;
  bool _imageMode = false;
  bool _imageBusy = false;
  int _imageRun = 0; // bumps to ignore a cancelled image request
  bool _listening = false;

  Chat get chat => widget.chat;
  AppState get app => widget.app;
  bool get busy => _sub != null || _imageBusy;

  @override
  void dispose() {
    _sub?.cancel();
    _speech.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- Sending ------------------------------------------------------------------------------

  void _submit() {
    if (_imageMode) {
      _sendImage();
    } else {
      _send();
    }
  }

  void _addUserMessage(String text) {
    chat.messages.add(Msg(role: 'user', text: text));
    if (chat.title.isEmpty) chat.title = text.length > 48 ? '${text.substring(0, 48)}…' : text;
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || busy) return;
    VibeHaptics.light();
    _stopListening();
    _input.clear();

    _addUserMessage(text);
    final history = <Map<String, String>>[
      if (chat.system.trim().isNotEmpty) {'role': 'system', 'content': chat.system.trim()},
      ...chat.messages
          .where((m) => !m.error && m.text.trim().isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.text}),
    ];

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

  Future<void> _sendImage() async {
    final prompt = _input.text.trim();
    if (prompt.isEmpty || busy) return;
    VibeHaptics.light();
    _stopListening();
    _input.clear();

    _addUserMessage(prompt);
    final reply = Msg(role: 'assistant', text: '');
    chat.messages.add(reply);
    app.chats.changed();
    final run = ++_imageRun;
    setState(() {
      _imageBusy = true;
      _streaming = reply;
    });
    try {
      final result = await app.api.generateImage(prompt);
      if (run != _imageRun) return;
      for (final bytes in result.images) {
        reply.images.add(await app.chats.saveImage(bytes));
      }
      reply.via = result.via;
    } catch (e) {
      if (run != _imageRun) return;
      reply.error = true;
      reply.text = e.toString();
    }
    if (run != _imageRun) return;
    _imageBusy = false;
    _finish();
  }

  void _finish() {
    final r = _streaming;
    if (r != null && r.text.trim().isEmpty && r.images.isEmpty && !r.error) {
      r.error = true;
      r.text = 'No reply. The model may be busy; try again or pick another model.';
    }
    _sub = null;
    _streaming = null;
    _imageBusy = false;
    chat.updated = DateTime.now().millisecondsSinceEpoch;
    app.chats.changed();
    if (mounted) setState(() {});
  }

  void _stop() {
    _sub?.cancel();
    _imageRun++;
    _finish();
  }

  // ---- Voice input (Android's built-in speech recognition) --------------------------------

  Future<void> _toggleMic() async {
    if (_listening) {
      _stopListening();
      return;
    }
    final ok = await _speech.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ok) {
      _snack('Voice input is not available on this phone.');
      return;
    }
    VibeHaptics.light();
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        _input.text = r.recognizedWords;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      },
    );
  }

  void _stopListening() {
    if (_listening) {
      _speech.stop();
      setState(() => _listening = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  // ---- UI -----------------------------------------------------------------------------------

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
                    app.modelName(chat.model) + (chat.system.trim().isNotEmpty ? ' · custom instructions' : ''),
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
            tooltip: 'Instructions',
            icon: Icon(Icons.tune, color: chat.system.trim().isNotEmpty ? VibeColors.blurple : VibeColors.muted),
            onPressed: _editSystem,
          ),
          if (chat.provider != 'fusion')
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
                        typing: identical(m, _streaming) && m.text.isEmpty && m.images.isEmpty,
                        imageMode: identical(m, _streaming) && _imageBusy,
                      );
                    },
                  ),
          ),
          _Composer(
            controller: _input,
            hint: _imageMode ? 'Describe an image…' : 'Message ${look.name}',
            busy: busy,
            imageMode: _imageMode,
            listening: _listening,
            onSend: _submit,
            onStop: _stop,
            onMic: _toggleMic,
            onToggleImage: () {
              VibeHaptics.selection();
              setState(() => _imageMode = !_imageMode);
            },
          ),
        ],
      ),
    );
  }

  void _editSystem() {
    final ctrl = TextEditingController(text: chat.system);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibeColors.card,
        title: const Text('Instructions for this chat'),
        content: TextField(
          controller: ctrl,
          minLines: 3,
          maxLines: 8,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Reply briefly, in simple English.',
            filled: true,
            fillColor: VibeColors.rail,
            border: OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
        actions: [
          if (chat.system.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => chat.system = '');
                app.chats.changed();
                Navigator.pop(ctx);
              },
              child: const Text('Clear'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() => chat.system = ctrl.text.trim());
              app.chats.changed();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
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
            switch (provider) {
              'auto' => 'Every message goes to the best free model available right now.',
              'fusion' => 'Several models answer each message at once, then one blended answer comes back. '
                  'Slower, but often better.',
              _ => 'This is the beginning of your chat with $name.',
            },
            style: const TextStyle(color: VibeColors.muted, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap the image button to create pictures, or the mic to talk.',
            style: TextStyle(color: VibeColors.faint, fontSize: 13),
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
  final bool imageMode;
  const _MessageRow({
    required this.msg,
    required this.header,
    required this.provider,
    required this.typing,
    required this.imageMode,
  });

  @override
  Widget build(BuildContext context) {
    final mine = msg.role == 'user';
    final via = msg.via;
    // Auto chats show the provider that actually answered.
    final answeredBy = !mine && via != null && via.contains('/') ? via.substring(0, via.indexOf('/')) : provider;
    final name = mine ? 'You' : lookFor(answeredBy).name;
    final time = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(msg.at)).format(context);

    final Widget body;
    if (typing) {
      body = Text(
        imageMode ? 'drawing…' : 'typing…',
        style: const TextStyle(color: VibeColors.faint, fontStyle: FontStyle.italic),
      );
    } else if (msg.error) {
      body = Text(msg.text, style: const TextStyle(color: VibeColors.danger, fontSize: 14.5));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.text.isNotEmpty)
            MarkdownBody(data: msg.text, selectable: true, styleSheet: _markdownStyle(context)),
          for (final path in msg.images)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: () => _viewImage(context, path),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Text('Image missing',
                          style: TextStyle(color: VibeColors.faint, fontStyle: FontStyle.italic)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

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

  static void _viewImage(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.file(File(path))),
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
  final bool imageMode;
  final bool listening;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onMic;
  final VoidCallback onToggleImage;
  const _Composer({
    required this.controller,
    required this.hint,
    required this.busy,
    required this.imageMode,
    required this.listening,
    required this.onSend,
    required this.onStop,
    required this.onMic,
    required this.onToggleImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: imageMode ? 'Back to chat' : 'Create an image',
                onPressed: busy ? null : onToggleImage,
                style: IconButton.styleFrom(
                  backgroundColor: imageMode ? VibeColors.blurple : VibeColors.high,
                ),
                icon: Icon(
                  imageMode ? Icons.image : Icons.image_outlined,
                  color: imageMode ? Colors.white : VibeColors.muted,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: VibeColors.high,
                  borderRadius: BorderRadius.circular(24),
                  border: listening ? Border.all(color: VibeColors.blurple, width: 1.5) : null,
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: VibeColors.text, fontSize: 16),
                  cursorColor: VibeColors.blurple,
                  decoration: InputDecoration(
                    hintText: listening ? 'Listening…' : hint,
                    hintStyle: const TextStyle(color: VibeColors.faint),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Mic while the box is empty, send once there is text (like Discord).
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                final IconData icon;
                final VoidCallback onTap;
                if (busy) {
                  icon = Icons.stop_rounded;
                  onTap = onStop;
                } else if (!hasText || listening) {
                  icon = listening ? Icons.mic : Icons.mic_none_rounded;
                  onTap = onMic;
                } else {
                  icon = imageMode ? Icons.brush_rounded : Icons.arrow_upward_rounded;
                  onTap = onSend;
                }
                return SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: busy
                          ? VibeColors.highest
                          : (listening || hasText ? VibeColors.blurple : VibeColors.high),
                    ),
                    onPressed: onTap,
                    icon: Icon(icon, color: Colors.white),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
