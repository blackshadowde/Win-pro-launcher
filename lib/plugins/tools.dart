import 'dart:convert';

/// A function the AI may call (OpenAI "tools" format).
class ToolSpec {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  /// Changes something (creates, edits, sends). Asks you before running.
  final bool writes;

  const ToolSpec(this.name, this.description, this.parameters, {this.writes = false});

  Map<String, dynamic> toOpenAi() => {
        'type': 'function',
        'function': {'name': name, 'description': description, 'parameters': parameters},
      };
}

/// One call the AI made, as streamed back.
class ToolCall {
  String id;
  String name;
  String arguments;

  /// Short result shown in the chat (e.g. "ok · 2.1 KB" or the error).
  String? outcome;

  ToolCall(this.id, this.name, this.arguments, {this.outcome});

  Map<String, dynamic> get args {
    try {
      final j = jsonDecode(arguments.isEmpty ? '{}' : arguments);
      return j is Map<String, dynamic> ? j : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> toOpenAi() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments.isEmpty ? '{}' : arguments},
      };

  Map<String, dynamic> toJson() => {'id': id, 'n': name, 'a': arguments, if (outcome != null) 'o': outcome};

  factory ToolCall.fromJson(Map<String, dynamic> j) => ToolCall(
        (j['id'] ?? '').toString(),
        (j['n'] ?? '').toString(),
        (j['a'] ?? '').toString(),
        outcome: j['o'] as String?,
      );
}

/// A group of tools with its own settings (GitHub, web reader, an MCP server…).
abstract class Plugin {
  String get id;
  String get name;
  String get description;

  /// Configured enough to offer its tools (e.g. has a token).
  bool get ready;

  List<ToolSpec> get tools;

  /// Runs a tool and returns text for the AI. Throw to report an error.
  Future<String> run(String tool, Map<String, dynamic> args);

  /// Short, human description of a call, shown in the chat and the approval prompt.
  String describe(String tool, Map<String, dynamic> args) {
    final parts = args.entries
        .where((e) => e.value is String || e.value is num || e.value is bool)
        .take(3)
        .map((e) => e.value.toString())
        .map((v) => v.length > 40 ? '${v.substring(0, 40)}…' : v);
    return parts.isEmpty ? tool : '$tool · ${parts.join(' · ')}';
  }
}

// Small helpers for writing JSON schemas.
Map<String, dynamic> schema(Map<String, Map<String, dynamic>> props, [List<String> required = const []]) => {
      'type': 'object',
      'properties': props,
      if (required.isNotEmpty) 'required': required,
    };

Map<String, dynamic> str(String description) => {'type': 'string', 'description': description};
Map<String, dynamic> integer(String description) => {'type': 'integer', 'description': description};

/// Keeps tool results small enough for free models' context windows.
String clip(String text, [int max = 12000]) =>
    text.length <= max ? text : '${text.substring(0, max)}\n…[cut: ${text.length - max} more characters]';
