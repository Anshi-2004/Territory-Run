import 'package:flutter/material.dart';

class AppTheme {
  // Brand & Map Conquest Colors
  static const Color darkBg = Color(0xFF090D16);
  static const Color surfaceColor = Color(0xFF131A26);
  static const Color surfaceLight = Color(0xFF1E2838);
  static const Color cardColor = Color(0xFF151D2A);

  // Vibrant Accents
  static const Color neonCyan = Color(0xFF00F0FF);
  static const Color neonPink = Color(0xFFFF0055);
  static const Color goldAmber = Color(0xFFFFB800);
  static const Color tacticalGreen = Color(0xFF00FF9D);
  static const Color imperialPurple = Color(0xFFB5179E);

  // Palette choices for player customization
  static const List<String> playerColorPalette = [
    "#00F0FF", // Neon Cyan
    "#FF0055", // Neon Pink
    "#00FF9D", // Tactical Green
    "#FFB800", // Gold Amber
    "#B5179E", // Imperial Purple
    "#3388FF", // Cobalt Blue
    "#FF7700", // Blaze Orange
    "#00E5FF", // Electric Blue
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: neonCyan,
      cardColor: cardColor,
      colorScheme: const ColorScheme.dark(
        primary: neonCyan,
        secondary: neonPink,
        surface: surfaceColor,
        tertiary: tacticalGreen,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonCyan,
          foregroundColor: Colors.black,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: surfaceLight, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: surfaceLight, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: neonCyan, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF8B949E)),
        hintStyle: const TextStyle(color: Color(0xFF484F58)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: neonCyan,
        unselectedItemColor: Color(0xFF8B949E),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
    );
  }
}
