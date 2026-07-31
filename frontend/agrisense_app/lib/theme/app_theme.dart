import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand Colors (Premium Agriculture Palette) ──
  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color accent = Color(0xFFFF9800);
  static const Color accentSoft = Color(0xFFFFC107);
  
  // Backgrounds
  static const Color bgLight = Color(0xFFF5F9F5);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgWeather = Color(0xFFE3F2FD);
  static const Color bgAdmin = Color(0xFF0F172A);
  static const Color bgAdminCard = Color(0xFF1E293B);
  static const Color bgDark = Color(0xFF111111);
  
  // Semantic
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF2196F3);
  
  // Text
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color textOnDark = Color(0xFFFFFFFF);
  
  // Payment
  static const Color mtnYellow = Color(0xFFFFCC00);
  static const Color orangeMoney = Color(0xFFFF6600);
  
  // Glass
  static const Color glassWhite = Color(0xB3FFFFFF);
  
  // ── Typography (Premium Modern) ──
  static TextStyle displayLarge = GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -1);
  static TextStyle displayMedium = GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.5);
  static TextStyle headlineSmall = GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary);
  static TextStyle titleLarge = GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary);
  static TextStyle titleMedium = GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary);
  static TextStyle bodyLarge = GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: textPrimary);
  static TextStyle bodyMedium = GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: textSecondary);
  static TextStyle bodySmall = GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: textSecondary);
  static TextStyle labelLarge = GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: textOnDark);
  static TextStyle labelMedium = GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: textSecondary);
  
  // ── Dimensions ──
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const double radiusFull = 999.0;
  
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  
  // ── Decorations ──
  static BoxDecoration get gradientBackground => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [primaryDark, primary, primaryLight],
    ),
  );
  
  static BoxDecoration get darkBackground => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [bgAdmin, Color(0xFF1E293B)],
    ),
  );
  
  // ── Card Decoration ──
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radiusLarge),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.06),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
  
  static BoxDecoration get cardBorder => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radiusLarge),
    border: Border.all(color: Colors.grey.shade200),
  );
}
