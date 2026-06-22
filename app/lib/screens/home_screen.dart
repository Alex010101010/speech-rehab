import 'package:flutter/material.dart';
import '../data/content_repository.dart';
import '../engine/progress_store.dart';
import '../engine/tts_service.dart';
import '../engine/achievements.dart';
import 'session_screen.dart';

class HomeScreen extends StatefulWidget {
  final ContentRepository repo;
  final ProgressStore store;
  final TtsService tts;
  const HomeScreen(
      {super.key,
      required this.repo,
      required this.store,
      required this.tts});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _ruVoiceOk = true; // пока не проверили — не пугаем подсказкой

  @override
  void initState() {
    super.initState();
    widget.tts.ensureReady().then((ok) {
      if (mounted) setState(() => _ruVoiceOk = ok);
    });
  }

  String _plant(int level) =>
      level >= 3 ? '🌳' : (level >= 2 ? '🌿' : '🌱');

  @override
  Widget build(BuildContext context) {
    final p = widget.store.progress;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_ruVoiceOk) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade700),
                        ),
                        child: const Text(
                          '⚠️ Русский голос не установлен — озвучка работать '
                          'не будет.\nУстановите его в настройках планшета: '
                          'Настройки → Система → Язык и ввод → Синтез речи → '
                          'добавить русский голос.',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    const Text('Занятие речью',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 38, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Text(_plant(p.level),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 96)),
                    const SizedBox(height: 8),
                    Text('Уровень ${p.level} · занятий: ${p.sessions}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => widget.tts.speak(
                          'Занятие речью. Нажмите «Начать занятие», чтобы заниматься. '
                          'Кнопка «Успехи» — посмотреть результаты.'),
                      icon: const Icon(Icons.volume_up),
                      label: const Text('Прослушать'),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => SessionScreen(
                              repo: widget.repo,
                              store: widget.store,
                              tts: widget.tts),
                        ));
                        if (mounted) setState(() {});
                      },
                      child: const Text('Начать занятие'),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => _showProgress(context, p),
                      child: const Text('Успехи'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showProgress(BuildContext context, Progress p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Успехи'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Занятий: ${p.sessions}',
                style: const TextStyle(fontSize: 20)),
            Text('Дней с занятиями: ${p.days.length}',
                style: const TextStyle(fontSize: 20)),
            Text('Ответов: ${p.answered}',
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            const Text('Награды:',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (p.achievements.isEmpty)
              const Text('Пока нет — всё впереди',
                  style: TextStyle(fontSize: 18))
            else
              ...p.achievements.map((a) => Text('• ${achievementTitle(a)}',
                  style: const TextStyle(fontSize: 18))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }
}
