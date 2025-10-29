// lib/theme/sm_theme.dart
import 'package:flutter/material.dart';

/// SallaeMallae 공통 팔레트 (피그마 느낌 + 실서비스화)
class SMColors {
  // Brand
  static const primary = Color(0xFF2D9CDB); // 피그마 블루 톤
  static const onPrimary = Colors.white;

  // Neutrals
  static const bg = Color(0xFFF7F8FA);
  static const surface = Colors.white;
  static const outline = Color(0xFFB9C1CC);
  static const text = Color(0xFF1C1F24);
  static const textSub = Color(0xFF667085);

  // States
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);
}

class SallaeTheme {
  static ThemeData light = _build(brightness: Brightness.light);
  static ThemeData dark = _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: SMColors.primary,
        brightness: brightness,
        primary: SMColors.primary,
        onPrimary: SMColors.onPrimary,
        surface: isDark ? const Color(0xFF111418) : SMColors.surface,
        background: isDark ? const Color(0xFF0B0E12) : SMColors.bg,
      ),
    );

    // 공통 폰트 굵기/간격(피그마 얇고 선명한 톤)
    final textTheme = base.textTheme
        .apply(bodyColor: SMColors.text, displayColor: SMColors.text)
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.25),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        );

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? base.colorScheme.background : SMColors.bg,
      textTheme: textTheme,

      // AppBar: 미니멀, 얇은 라인 느낌
      appBarTheme: AppBarTheme(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: base.colorScheme.surface,
        foregroundColor: SMColors.text,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      ),

      // Card: 그림자 최소, 둥근 정도 살짝 ↑
      cardTheme: CardThemeData( // <- 변경: CardThemeData
        color: base.colorScheme.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
      ),

      // ListTile: 밀도 낮추고 텍스트 선명
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        horizontalTitleGap: 10,
        minLeadingWidth: 24,
      ),

      // 입력창: 박스형, 라운드 작게, 얇은 테두리
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark ? const Color(0xFF1A1F24) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: SMColors.outline.withOpacity(0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: SMColors.outline.withOpacity(0.6)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: SMColors.primary, width: 1.4),
        ),
        hintStyle: const TextStyle(color: SMColors.textSub),
        labelStyle: const TextStyle(color: SMColors.textSub),
      ),

      // 버튼: Filled/Outlined 통일 (모서리 10, 높이 44)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          textStyle: textTheme.labelLarge,
          side: const BorderSide(color: SMColors.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),

      // Chip: 카테고리/필터가 피그마 느낌으로
      chipTheme: base.chipTheme.copyWith(
        shape: StadiumBorder(side: BorderSide(color: SMColors.outline.withOpacity(0.7))),
        labelStyle: textTheme.bodyMedium?.copyWith(color: SMColors.text),
        side: BorderSide(color: SMColors.outline.withOpacity(0.7)),
        selectedColor: SMColors.primary.withOpacity(.12),
        disabledColor: base.disabledColor,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),

      // Divider/Outline
      dividerTheme: DividerThemeData(
        color: SMColors.outline.withOpacity(0.4),
        thickness: 1,
        space: 0,
      ),
    );
  }
}
