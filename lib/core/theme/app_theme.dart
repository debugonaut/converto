import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFF171819);
  static const surface = Color(0xFF202122);
  static const border = Color(0xFF383A3B);
  static const muted = Color(0xFFABAEAE);
  static const amber = Color(0xFFF4BE64);
  static const teal = Color(0xFF78CCB4);

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    platform: TargetPlatform.macOS,
    fontFamily: '.AppleSystemUIFont',
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: amber,
      onPrimary: Color(0xFF211A0F),
      secondary: teal,
      surface: surface,
      onSurface: Color(0xFFF2F1ED),
      onSurfaceVariant: muted,
      outline: border,
      error: Color(0xFFFFA69D),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
      ),
      headlineSmall: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -.6,
      ),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
    ),
    dividerTheme: const DividerThemeData(color: border, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: amber, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFF2F1ED),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: amber.withValues(alpha: .15),
      side: const BorderSide(color: border),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      labelStyle: const TextStyle(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}
