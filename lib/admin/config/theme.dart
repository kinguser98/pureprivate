import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0F19),
      
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0F19),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1F2E).withOpacity(0.5),
        margin: const EdgeInsets.all(8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1A1F2E).withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
        bodySmall: TextStyle(color: Colors.white70),
        labelLarge: TextStyle(color: Colors.white),
        labelMedium: TextStyle(color: Colors.white70),
        labelSmall: TextStyle(color: Colors.white54),
      ),
      
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFEF4444),
        secondary: Color(0xFF8B5CF6),
        surface: Color(0xFF1A1F2E),
        onSurface: Colors.white,
        error: Color(0xFFEF4444),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: Colors.white.withOpacity(0.3)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      
      iconTheme: const IconThemeData(color: Colors.white),
      
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF1A1F2E),
        selectedItemColor: const Color(0xFFEF4444),
        unselectedItemColor: Colors.white.withOpacity(0.5),
        type: BottomNavigationBarType.fixed,
      ),
      
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFFEF4444),
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
      
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.1),
        thickness: 1,
      ),
      
      listTileTheme: ListTileThemeData(
        iconColor: Colors.white,
        textColor: Colors.white,
        tileColor: const Color(0xFF1A1F2E).withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
