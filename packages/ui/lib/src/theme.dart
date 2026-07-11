import 'package:flutter/material.dart';

/// ZVComm Material 3 theme (dark-friendly for field use).
abstract final class ZvcommTheme {
  static const Color seed = Color(0xFF00BFA5);

  static ThemeData light() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      );

  static ThemeData dark() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      );
}
