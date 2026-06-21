import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/exercise.dart';

/// Загружает все наборы заданий из ассетов по манифесту index.json.
class ContentRepository {
  final Map<String, ExerciseSet> _sets = {};

  Future<void> load() async {
    final indexStr = await rootBundle.loadString('assets/content/index.json');
    final index = jsonDecode(indexStr) as Map<String, dynamic>;
    final types = (index['types'] as List).cast<dynamic>();
    for (final t in types) {
      final m = Map<String, dynamic>.from(t as Map);
      final file = (m['file'] ?? '').toString(); // напр. "json/01_find_error.json"
      final base = file.contains('/') ? file.split('/').last : file;
      if (base.isEmpty) continue;
      final raw = await rootBundle.loadString('assets/content/$base');
      final set = ExerciseSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _sets[set.type] = set;
    }
  }

  ExerciseSet? operator [](String type) => _sets[type];
  bool has(String type) => _sets.containsKey(type);
  Iterable<String> get types => _sets.keys;
  int get total => _sets.values.fold(0, (a, s) => a + s.items.length);
}
