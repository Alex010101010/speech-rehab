import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/content_overlay.dart';
import '../data/content_repository.dart';
import '../engine/progress_store.dart';
import '../engine/tts_service.dart';
import '../engine/achievements.dart';
import 'session_screen.dart';

class HomeScreen extends StatefulWidget {
  final ContentRepository repo;
  final ProgressStore store;
  final TtsService tts;
  final ContentOverlay overlay;
  const HomeScreen(
      {super.key,
      required this.repo,
      required this.store,
      required this.tts,
      required this.overlay});
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
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => _showSettings(context),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Настройки',
                          style: TextStyle(fontSize: 18)),
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

  void _showSettings(BuildContext context) {
    final p = widget.store.progress;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Настройки'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Картиночный режим',
                    style: TextStyle(fontSize: 20)),
                subtitle: const Text(
                    'Словарные задания — только узнаванием по картинке',
                    style: TextStyle(fontSize: 15)),
                value: p.pictureMode,
                onChanged: (v) async {
                  setLocal(() => p.pictureMode = v);
                  await widget.store.save();
                  if (mounted) setState(() {});
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: const Text('Проверить обновления',
                    style: TextStyle(fontSize: 20)),
                subtitle: const Text('Загрузить свежие задания',
                    style: TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(context);
                  _checkUpdates();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Отчёт для логопеда',
                    style: TextStyle(fontSize: 20)),
                subtitle: const Text('Срез прогресса текстом — отправить',
                    style: TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(context);
                  _showReport(p);
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Сохранить копию прогресса',
                    style: TextStyle(fontSize: 20)),
                subtitle: const Text('Код для переноса на другое устройство',
                    style: TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(context);
                  _showExport();
                },
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Восстановить из копии',
                    style: TextStyle(fontSize: 20)),
                subtitle: const Text('Вставить ранее сохранённый код',
                    style: TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(context);
                  _showImport();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Проверяю обновления…')));
    final r = await widget.overlay.checkForUpdate();
    final msg = switch (r.status) {
      OtaStatus.updated =>
        'Обновление загружено. Изменения появятся после перезапуска.',
      OtaStatus.upToDate => 'У вас уже последняя версия заданий.',
      OtaStatus.offline => 'Нет связи с сервером. Попробуйте позже.',
      OtaStatus.skipped => 'Обновление сейчас недоступно.',
      OtaStatus.error => 'Не удалось обновить. Попробуйте позже.',
    };
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showExport() {
    final code = widget.store.exportCode();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Копия прогресса'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Нажмите «Скопировать» и вставьте этот код в письмо себе '
                'или в заметку. По нему можно восстановить прогресс на '
                'другом устройстве.',
                style: TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(code,
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Код скопирован')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Скопировать', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  void _showImport() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Восстановить прогресс'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Вставьте код копии. Текущий прогресс на этом устройстве '
                'будет заменён.',
                style: TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 5,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Вставьте код сюда',
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  final t = d?.text;
                  if (t != null) controller.text = t;
                },
                icon: const Icon(Icons.paste),
                label: const Text('Вставить из буфера',
                    style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton(
            onPressed: () async {
              final ok = await widget.store.importCode(controller.text);
              if (!mounted) return;
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              if (ok) {
                setState(() {});
                messenger.showSnackBar(const SnackBar(
                    content: Text('Прогресс восстановлен')));
              } else {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Код не распознан. Проверьте, что '
                        'скопировали его целиком.')));
              }
            },
            child: const Text('Восстановить', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  // "2026-06-24" → "24.06" для компактной динамики
  String _shortDay(String iso) {
    final parts = iso.split('-');
    return parts.length == 3 ? '${parts[2]}.${parts[1]}' : iso;
  }

  String _skillLabel(String type) {
    final t = widget.repo[type]?.title;
    if (t != null && t.isNotEmpty) return t;
    const fallback = {
      'clock': 'Время по часам',
      'stress': 'Ударение в слове',
      'picture_word': 'Узнавание по картинке',
      'yesno_picture': 'Да/нет: слово и картинка',
      'syllables': 'Слово из слогов',
      'match_pairs': 'Соединить пары',
      'auto_series': 'Продолжить ряд',
    };
    return fallback[type] ?? type;
  }

  /// Человекочитаемый отчёт для логопеда — срез прогресса на сейчас.
  String _buildReport(Progress p) {
    final acc = p.answered > 0 ? (p.correct * 100 / p.answered).round() : 0;
    final now = DateTime.now();
    final date = '${now.day.toString().padLeft(2, '0')}.'
        '${now.month.toString().padLeft(2, '0')}.${now.year}';
    final b = StringBuffer();
    b.writeln('Отчёт по занятиям речью');
    b.writeln('Дата: $date');
    b.writeln('');
    b.writeln('Занятий проведено: ${p.sessions}');
    b.writeln('Дней с занятиями: ${p.days.length}');
    b.writeln(
        'Ответов: ${p.answered}, из них верно: ${p.correct} (точность $acc%)');
    b.writeln('Режим: ${p.pictureMode ? 'картиночный' : 'обычный'}');
    b.writeln('Общий уровень: ${p.level} (из 3)');
    if (p.skillLevels.isNotEmpty) {
      b.writeln('');
      b.writeln('Уровень по навыкам (0–3):');
      final entries = p.skillLevels.entries.toList()
        ..sort((a, c) => _skillLabel(a.key).compareTo(_skillLabel(c.key)));
      for (final e in entries) {
        b.writeln('• ${_skillLabel(e.key)}: ${e.value}');
      }
    }
    if (p.history.isNotEmpty) {
      b.writeln('');
      b.writeln('Динамика последних занятий:');
      final recent = p.history.length > 8
          ? p.history.sublist(p.history.length - 8)
          : p.history;
      for (final s in recent) {
        final ans = (s['answered'] ?? 0) as int;
        final cor = (s['correct'] ?? 0) as int;
        final lvl = (s['level'] ?? 0) as int;
        final pct = ans > 0 ? (cor * 100 / ans).round() : 0;
        b.writeln('• ${_shortDay(s['day']?.toString() ?? '')}: '
            '$cor/$ans ($pct%), уровень $lvl');
      }
    }
    b.writeln('');
    b.writeln('Награды: ${p.achievements.isEmpty ? 'пока нет' : p.achievements.map(achievementTitle).join(', ')}');
    return b.toString();
  }

  void _showReport(Progress p) {
    final report = _buildReport(p);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Отчёт для логопеда'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Нажмите «Скопировать» и отправьте этот отчёт логопеду '
                '(почта, мессенджер).',
                style: TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(report,
                    style: const TextStyle(fontSize: 15)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Отчёт скопирован')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Скопировать', style: TextStyle(fontSize: 18)),
          ),
        ],
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
