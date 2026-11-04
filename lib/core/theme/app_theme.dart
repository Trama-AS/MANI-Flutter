import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño oficial de MANI — Neo-Brutalismo.
/// Extraído directamente de los prototipos oficiales de Figma:
/// - Fondo principal: #FDFBF7 (Crema cálido)
/// - Primario / Acento insignia: #FACC15 (Amarillo MANI)
/// - Bordes y contrastes: #1E1E1E (Negro carbón)
/// - Superficies / Tarjetas: #FFFFFF
/// - Textos secundarios: #6B7280
/// - Sombras duras (Hard Shadows): sin desenfoque (offset con color #1E1E1E)
/// - Tipografía: Plus Jakarta Sans
class AppTheme {
  AppTheme._();

  // ── Colores base ──────────────────────────────────────────────────────────
  static const Color background = Color(0xFFFDFBF7); // Crema de fondo oficial
  static const Color surface = Color(0xFFFFFFFF); // Blanco
  static const Color primary = Color(
    0xFFFACC15,
  ); // Amarillo característico MANI
  static const Color dark = Color(0xFF1E1E1E); // Tinta negra / bordes
  static const Color textPrimary = Color(0xFF1E1E1E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color borderLight = Color(0xFFE5E7EB);

  // ── Colores de estado ─────────────────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);

  // ── Sombras neo-brutalistas ───────────────────────────────────────────────
  static const BoxShadow hardShadowSm = BoxShadow(
    color: dark,
    offset: Offset(2, 2),
    blurRadius: 0,
  );

  static const BoxShadow hardShadowMd = BoxShadow(
    color: dark,
    offset: Offset(4, 4),
    blurRadius: 0,
  );

  static const BoxShadow hardShadowLg = BoxShadow(
    color: dark,
    offset: Offset(6, 6),
    blurRadius: 0,
  );

  // ── Radios de borde ───────────────────────────────────────────────────────
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusXl = 12.0;
  static const double radius2xl = 16.0;

  static ThemeData get light {
    final textTheme = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: textPrimary,
        secondary: primary,
        onSecondary: textPrimary,
        surface: surface,
        onSurface: textPrimary,
        error: error,
      ),
      textTheme: textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: dark,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: dark,
        ),
        shape: const Border(bottom: BorderSide(color: dark, width: 2)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius2xl),
          side: const BorderSide(color: dark, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: primary,
        selectedColor: primary,
        secondarySelectedColor: primary,
        disabledColor: borderLight,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        side: const BorderSide(color: dark, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: dark,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: dark,
          disabledBackgroundColor: borderLight,
          disabledForegroundColor: textSecondary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXl),
            side: const BorderSide(color: dark, width: 2),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: dark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXl),
            side: const BorderSide(color: dark, width: 2),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: dark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
          side: const BorderSide(color: dark, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXl),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: dark,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          borderSide: const BorderSide(color: dark, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          borderSide: const BorderSide(color: dark, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          borderSide: const BorderSide(color: dark, width: 2.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          borderSide: const BorderSide(color: error, width: 2.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius2xl),
          side: const BorderSide(color: dark, width: 2.5),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: dark,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: dark, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: surface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: primary, width: 2),
        ),
      ),
      dividerTheme: const DividerThemeData(color: dark, thickness: 1.5),
    );
  }
}
