import 'package:flutter/material.dart';

/// Тема под доступность 70+: крупный шрифт, высокий контраст, большие кнопки.
ThemeData buildTheme() {
  const seed = Color(0xFF1565C0);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seed),
    scaffoldBackgroundColor: const Color(0xFFF7F7F5),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontSizeFactor: 1.25),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(72),
        textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
