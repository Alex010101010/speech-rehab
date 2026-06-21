import 'progress_store.dart';

String achievementTitle(String id) {
  switch (id) {
    case 'first':
      return 'Первое занятие';
    case 'week':
      return 'Неделя занятий';
    case 'hundred':
      return '100 ответов';
    case 'level2':
      return 'Новый уровень — 2';
    case 'level3':
      return 'Новый уровень — 3';
    default:
      return id;
  }
}

/// Пересчитывает награды. Возвращает только что добавленные (для показа).
/// Награды никогда не снимаются — только накопление, без наказаний.
List<String> updateAchievements(Progress p) {
  final added = <String>[];
  void add(String id) {
    if (!p.achievements.contains(id)) {
      p.achievements.add(id);
      added.add(id);
    }
  }

  if (p.sessions >= 1) add('first');
  if (p.days.length >= 7) add('week');
  if (p.answered >= 100) add('hundred');
  if (p.level >= 2) add('level2');
  if (p.level >= 3) add('level3');
  return added;
}
