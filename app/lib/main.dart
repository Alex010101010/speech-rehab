import 'dart:async';

import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'data/content_overlay.dart';
import 'data/content_repository.dart';
import 'engine/progress_store.dart';
import 'engine/tts_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RechApp());
}

class RechApp extends StatefulWidget {
  const RechApp({super.key});
  @override
  State<RechApp> createState() => _RechAppState();
}

class _RechAppState extends State<RechApp> {
  final ContentOverlay overlay = createContentOverlay();
  late final ContentRepository repo = ContentRepository(overlay: overlay);
  final ProgressStore store = ProgressStore();
  final TtsService tts = TtsService();
  late final Future<void> _init = _load();

  Future<void> _load() async {
    await overlay.init();
    contentOverlay = overlay; // для виджетов картинок (OtaImage)
    await repo.load();
    tts.setStress(await repo.loadStress());
    await store.load();
    // Фоновая проверка обновления контента: не блокирует вход в сессию,
    // применённое обновление вступит в силу со следующего запуска.
    unawaited(overlay.checkForUpdate());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Речь',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: FutureBuilder<void>(
        future: _init,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Ошибка загрузки данных:\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20)),
                ),
              ),
            );
          }
          return HomeScreen(
              repo: repo, store: store, tts: tts, overlay: overlay);
        },
      ),
    );
  }
}
