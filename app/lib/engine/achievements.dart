import 'progress_store.dart';

const Map<String, String> _titles = {
  'first': 'Первое занятие',
  's5': '5 занятий',
  's10': '10 занятий',
  's25': '25 занятий',
  's50': '50 занятий',
  'd3': '3 дня практики',
  'week': '7 дней практики',
  'd14': '2 недели практики',
  'd30': 'Месяц практики',
  'a50': '50 ответов',
  'hundred': '100 ответов',
  'a250': '250 ответов',
  'a500': '500 ответов',
  'level2': 'Новый уровень — 2',
  'level3': 'Новый уровень — 3',
};

String achievementTitle(String id) => _titles[id] ?? id;

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

  // занятия
  if (p.sessions >= 1) add('first');
  if (p.sessions >= 5) add('s5');
  if (p.sessions >= 10) add('s10');
  if (p.sessions >= 25) add('s25');
  if (p.sessions >= 50) add('s50');
  // дни практики (по сумме, не подряд)
  if (p.days.length >= 3) add('d3');
  if (p.days.length >= 7) add('week');
  if (p.days.length >= 14) add('d14');
  if (p.days.length >= 30) add('d30');
  // ответы
  if (p.answered >= 50) add('a50');
  if (p.answered >= 100) add('hundred');
  if (p.answered >= 250) add('a250');
  if (p.answered >= 500) add('a500');
  // уровень
  if (p.level >= 2) add('level2');
  if (p.level >= 3) add('level3');
  return added;
}
