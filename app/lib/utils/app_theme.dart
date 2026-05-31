import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const primary = Color(0xFF1A237E);
  static const primaryLight = Color(0xFF3949AB);

  static const scaffoldLight = Color(0xFFF4F6FA);
  static const scaffoldDark = Color(0xFF0F0F0F);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C1C1E);
  static const surface2Dark = Color(0xFF252528);

  static const borderLight = Color(0xFFE8EAED);
  static const borderDark = Color(0xFF2C2C2E);

  static const textPrimary = Color(0xFF0D0D0D);
  static const textSecondary = Color(0xFF6C757D);
  static const textTertiary = Color(0xFFADB5BD);

  static const live = Color(0xFF22C55E);
  static const win = Color(0xFF3B82F6);
  static const lose = Color(0xFFEF4444);

  AppColors._();
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness br) {
    final isDark = br == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Pretendard',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: br,
      ),
      scaffoldBackgroundColor:
          isDark ? AppColors.scaffoldDark : AppColors.scaffoldLight,
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.8,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? AppColors.scaffoldDark : AppColors.surfaceLight,
        foregroundColor:
            isDark ? const Color(0xFFF5F5F5) : AppColors.textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: isDark ? const Color(0xFFF5F5F5) : AppColors.primary,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: isDark
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
              )
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
              ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        selectedItemColor:
            isDark ? const Color(0xFF7B8FFF) : AppColors.primary,
        unselectedItemColor: AppColors.textTertiary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 10),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.normal, fontSize: 10),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.borderDark : AppColors.borderLight,
        thickness: 0.8,
        space: 0,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: isDark ? AppColors.borderDark : AppColors.borderLight,
        indicatorColor:
            isDark ? const Color(0xFF7B8FFF) : AppColors.primary,
        labelColor: isDark ? const Color(0xFF7B8FFF) : AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'Pretendard'),
        unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500, fontSize: 13, fontFamily: 'Pretendard'),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surface2Dark : AppColors.scaffoldLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
              width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryLight, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, fontFamily: 'Pretendard'),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? const Color(0xFF7B8FFF) : AppColors.primary,
          textStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontFamily: 'Pretendard'),
        ),
      ),
    );
  }
}
