import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One palette and interaction language across capture, editing and account UI.
abstract final class AuraColors {
  static const background = Color(0xFF0B0E17);
  static const surface = Color(0xFF151A27);
  static const raised = Color(0xFF202738);
  static const border = Color(0xFF323B50);
  static const text = Color(0xFFF3F5FC);
  static const muted = Color(0xFFADB7CC);
  static const primary = Color(0xFFB5A1FF);
  static const violet = Color(0xFF7550D8);
  static const pink = Color(0xFFBC347F);
  static const blue = Color(0xFF69A5FF);
  static const green = Color(0xFF57D9A1);
  static const yellow = Color(0xFFFFE16B);
  static const error = Color(0xFFFF8795);
  static const recording = Color(0xFFE64B65);
  static const scrim = Color(0xCF0B0E17);
  static const gradient = [violet, pink, Color(0xFF326ACB)];
  static const brandGradient = LinearGradient(
    colors: gradient,
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

abstract final class AuraTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AuraColors.primary,
      onPrimary: AuraColors.background,
      secondary: AuraColors.green,
      onSecondary: AuraColors.background,
      tertiary: AuraColors.yellow,
      onTertiary: AuraColors.background,
      surface: AuraColors.surface,
      onSurface: AuraColors.text,
      onSurfaceVariant: AuraColors.muted,
      outline: AuraColors.border,
      error: AuraColors.error,
      onError: AuraColors.background,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AuraColors.background,
      canvasColor: AuraColors.surface,
      dividerColor: AuraColors.border,
      dividerTheme: const DividerThemeData(
        color: AuraColors.border,
        thickness: 1,
      ),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          height: 1.15,
          color: AuraColors.text,
        ),
        headlineSmall: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: AuraColors.text,
        ),
        titleLarge: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: AuraColors.text,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AuraColors.text,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          height: 1.45,
          color: AuraColors.text,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          height: 1.4,
          color: AuraColors.muted,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AuraColors.text,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AuraColors.background,
        foregroundColor: AuraColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 8,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AuraColors.primary,
          foregroundColor: AuraColors.background,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: shape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AuraColors.primary,
          foregroundColor: AuraColors.background,
          elevation: 0,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AuraColors.text,
          minimumSize: const Size(48, 48),
          shape: shape,
          side: const BorderSide(color: AuraColors.border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AuraColors.primary,
          minimumSize: const Size(48, 48),
          shape: shape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AuraColors.text,
          minimumSize: const Size(48, 48),
          iconSize: 22,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AuraColors.background,
        contentPadding: const EdgeInsets.all(16),
        labelStyle: const TextStyle(color: AuraColors.muted),
        hintStyle: const TextStyle(color: AuraColors.muted),
        prefixIconColor: AuraColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuraColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuraColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AuraColors.primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: AuraColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AuraColors.border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AuraColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(maxWidth: 640),
        dragHandleColor: AuraColors.muted,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AuraColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AuraColors.raised,
        contentTextStyle: const TextStyle(color: AuraColors.text, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AuraColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        checkmarkColor: AuraColors.primary,
        backgroundColor: AuraColors.surface,
        selectedColor: AuraColors.primary.withValues(alpha: .18),
        labelStyle: const TextStyle(
          color: AuraColors.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: AuraColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AuraColors.green
              : AuraColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AuraColors.green.withValues(alpha: .2)
              : AuraColors.raised,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AuraColors.primary,
        linearTrackColor: AuraColors.raised,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AuraColors.raised,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: AuraColors.text),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AuraColors.muted,
        textColor: AuraColors.text,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
