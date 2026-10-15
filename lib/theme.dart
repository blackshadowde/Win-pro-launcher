import 'package:flutter/material.dart';

import 'ui/vibe_swipe.dart';

/// Vibe's Discord palette (from Vibe-flutter's dark theme).
class VibeColors {
  static const blurple = Color(0xFF5865F2);
  static const rail = Color(0xFF121214);
  static const pane = Color(0xFF1E1D22);
  static const chat = Color(0xFF1A191E);
  static const card = Color(0xFF252429);
  static const high = Color(0xFF29282D);
  static const highest = Color(0xFF323136);
  static const text = Color(0xFFF2F3F5);
  static const muted = Color(0xFFB5BAC1);
  static const faint = Color(0xFF949BA4);
  static const outline = Color(0xFF3A393F);
  static const online = Color(0xFF23A55A);
  static const idle = Color(0xFFF0B232);
  static const danger = Color(0xFFF23F42);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: VibeColors.blurple,
    onPrimary: Colors.white,
    secondary: VibeColors.muted,
    surface: VibeColors.chat,
    onSurface: VibeColors.text,
    error: VibeColors.danger,
    outline: Color(0xFF6D6F78),
    outlineVariant: VibeColors.outline,
    surfaceContainerLowest: VibeColors.rail,
    surfaceContainerLow: VibeColors.pane,
    surfaceContainer: VibeColors.card,
    surfaceContainerHigh: VibeColors.high,
    surfaceContainerHighest: VibeColors.highest,
    onSurfaceVariant: VibeColors.muted,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Figtree',
    scaffoldBackgroundColor: VibeColors.chat,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: VibeColors.chat,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        // Vibe's Discord-style slide-over, draggable back from anywhere.
        TargetPlatform.android: VibePageTransitionsBuilder(),
        TargetPlatform.iOS: VibePageTransitionsBuilder(),
      },
    ),
  );
}
