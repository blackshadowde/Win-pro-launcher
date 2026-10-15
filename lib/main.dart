import 'package:flutter/material.dart';

import 'app_state.dart';
import 'home.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.init();
  runApp(VibeAiApp(app: app));
}

class VibeAiApp extends StatelessWidget {
  final AppState app;
  const VibeAiApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vibe AI',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(app: app),
    );
  }
}
