import 'package:flutter/material.dart';

import 'theme.dart';

/// How a provider looks in the rail: display name, colour, initials.
class ProviderLook {
  final String id;
  final String name;
  final Color color;
  final String initials;
  const ProviderLook(this.id, this.name, this.color, this.initials);
}

const _names = {
  'auto': 'Auto',
  'fusion': 'Fusion',
  'freellmapi': 'Auto',
  'google': 'Gemini',
  'gemini': 'Gemini',
  'groq': 'Groq',
  'cerebras': 'Cerebras',
  'openrouter': 'OpenRouter',
  'mistral': 'Mistral',
  'nvidia': 'NVIDIA',
  'cohere': 'Cohere',
  'cloudflare': 'Cloudflare',
  'huggingface': 'Hugging Face',
  'github': 'GitHub Models',
  'zai': 'Z.ai',
  'sambanova': 'SambaNova',
  'together': 'Together',
  'chutes': 'Chutes',
  'ollama': 'Ollama',
  'siliconflow': 'SiliconFlow',
  'modelscope': 'ModelScope',
  'pollinations': 'Pollinations',
  'llm7': 'LLM7',
};

const _palette = [
  Color(0xFF5865F2),
  Color(0xFFEB459E),
  Color(0xFF3BA55C),
  Color(0xFFFAA61A),
  Color(0xFFED4245),
  Color(0xFF9B59B6),
  Color(0xFF1ABC9C),
  Color(0xFFE67E22),
  Color(0xFF3498DB),
  Color(0xFF7289DA),
];

ProviderLook lookFor(String id) {
  final key = id.toLowerCase();
  final name = _names[key] ?? _titleCase(id);
  final words = name.split(RegExp(r'[\s._-]+')).where((w) => w.isNotEmpty).toList();
  final initials = words.length >= 2
      ? (words[0][0] + words[1][0]).toUpperCase()
      : name.substring(0, name.length >= 2 ? 2 : name.length).toUpperCase();
  var hash = 0;
  for (final c in key.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return ProviderLook(id, name, _palette[hash % _palette.length], initials);
}

/// Display name for "provider/model" from X-Routed-Via.
String viaLabel(String via) {
  final slash = via.indexOf('/');
  if (slash <= 0) return via;
  return '${lookFor(via.substring(0, slash)).name} · ${via.substring(slash + 1)}';
}

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Round avatar for a rail entry; turns into a rounded square when selected (Discord).
class ProviderAvatar extends StatelessWidget {
  final String id;
  final double size;
  final bool selected;
  const ProviderAvatar({super.key, required this.id, this.size = 48, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final look = lookFor(id);
    final isAuto = id == 'auto';
    final isFusion = id == 'fusion';
    final special = isAuto || isFusion;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: special ? null : (selected ? look.color : VibeColors.highest),
        gradient: isAuto
            ? const LinearGradient(
                colors: [VibeColors.blurple, Color(0xFFEB459E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : isFusion
                ? const LinearGradient(
                    colors: [Color(0xFF1ABC9C), VibeColors.blurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
        borderRadius: BorderRadius.circular(selected ? size * 0.32 : size / 2),
      ),
      alignment: Alignment.center,
      child: special
          ? Icon(isAuto ? Icons.auto_awesome : Icons.hub_outlined, color: Colors.white, size: size * 0.46)
          : Text(
              look.initials,
              style: TextStyle(
                color: selected ? Colors.white : look.color,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.33,
              ),
            ),
    );
  }
}

/// Colour for a provider's key health dot. Null = no dot.
Color? healthColor(String? health) => switch (health) {
      'healthy' => VibeColors.online,
      'rate_limited' => VibeColors.idle,
      'problem' => VibeColors.danger,
      _ => null,
    };
