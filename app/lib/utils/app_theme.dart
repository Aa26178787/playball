import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // hi-fi mockup ink 톤 (네이비 → 검정)
  static const primary = Color(0xFF111113);
  static const primaryLight = Color(0xFF3F3F46);
  // dark mode primary (alt: 흰 톤 강조 — Apple HIG 따라 순백 회피)
  static const primaryDark = Color(0xFFE5E5E7);

  static const scaffoldLight = Color(0xFFFAFAFB);
  static const scaffoldDark = Color(0xFF111113);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF18181C);
  static const surface2Dark = Color(0xFF1F1F24);

  static const borderLight = Color(0xFFEDEDF0);
  static const borderDark = Color(0xFF33333A);

  static const textPrimary = Color(0xFF111113);
  static const textSecondary = Color(0xFF6B6B73);
  static const textTertiary = Color(0xFF9A9AA2);

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
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      fontFamily: 'Pretendard',
      // 한글 가독성 — line-height 1.4, letterSpacing 0 (음수 자간 제거)
      textTheme: const TextTheme(
        bodyLarge:   TextStyle(fontSize: 16, height: 1.4, letterSpacing: 0),
        bodyMedium:  TextStyle(fontSize: 14, height: 1.4, letterSpacing: 0),
        bodySmall:   TextStyle(fontSize: 12, height: 1.4, letterSpacing: 0),
        titleLarge:  TextStyle(fontSize: 20, height: 1.3, letterSpacing: 0, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 16, height: 1.3, letterSpacing: 0, fontWeight: FontWeight.w700),
        titleSmall:  TextStyle(fontSize: 14, height: 1.3, letterSpacing: 0, fontWeight: FontWeight.w600),
        labelLarge:  TextStyle(fontSize: 14, height: 1.2, letterSpacing: 0, fontWeight: FontWeight.w600),
      ),
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
            isDark ? AppColors.scaffoldDark : AppColors.scaffoldLight,
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
            isDark ? AppColors.primaryDark : AppColors.primary,
        unselectedItemColor: AppColors.textTertiary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.normal, fontSize: 11),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.borderDark : AppColors.borderLight,
        thickness: 0.8,
        space: 0,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: isDark ? AppColors.borderDark : AppColors.borderLight,
        indicatorColor:
            isDark ? AppColors.primaryDark : AppColors.primary,
        labelColor: isDark ? AppColors.primaryDark : AppColors.primary,
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
          foregroundColor: isDark ? AppColors.primaryDark : AppColors.primary,
          textStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontFamily: 'Pretendard'),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF111113),
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Pretendard'),
        actionTextColor: Color(0xFFFFA000),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    );
  }
}
