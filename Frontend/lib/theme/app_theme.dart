import 'package:flutter/material.dart';
import 'brand_colors.dart';

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: BrandColors.primary,
    primary: BrandColors.primary,
    secondary: BrandColors.secondary,
    tertiary: BrandColors.alert,
    surface: BrandColors.surface,
    background: BrandColors.surface,
    brightness: Brightness.light,
  ).copyWith(error: BrandColors.alert);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: BrandColors.surface,

    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: BrandColors.textPrimary,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: BrandColors.textPrimary,
      ),
    ),

    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w700, color: BrandColors.textPrimary),
      bodyMedium: TextStyle(color: BrandColors.textSecondary),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BrandColors.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      labelStyle: const TextStyle(color: BrandColors.textSecondary),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: .2),
      ),
    ),

    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),

    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 10,
      // 8% negro sin usar withOpacity:
      shadowColor: Color(0x14000000),
      // Evita el tinte M3 en superficies blancas
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
    ),
  );
}