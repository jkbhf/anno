import 'package:flutter/material.dart';

/// Dark theme with strong accents - the game runs in the evening in a group,
/// and a bright screen is blinding then.
ThemeData buildTheme() {
  const seed = Color(0xFF7C4DFF);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF12101A),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1D1A28),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1D1A28),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

/// Colour for a decade - gives the revealed year something to recognize.
Color decadeColor(int year) {
  const palette = [
    Color(0xFF8E6BFF),
    Color(0xFF4D8BFF),
    Color(0xFF00B3A6),
    Color(0xFF3FA34D),
    Color(0xFFD9A400),
    Color(0xFFE8743B),
    Color(0xFFE0447B),
  ];
  return palette[((year ~/ 10) % palette.length).abs()];
}
