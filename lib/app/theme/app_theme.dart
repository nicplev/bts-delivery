import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'brand_colors.dart';

class AppTheme {
  AppTheme._();

  static const textTheme = TextTheme(
    displayLarge: TextStyle(
        fontSize: 42,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.8,
        height: 1.08,
        color: AppTokens.ink),
    displayMedium: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.3,
        height: 1.12,
        color: AppTokens.ink),
    displaySmall: TextStyle(
        fontSize: 29,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        height: 1.15,
        color: AppTokens.ink),
    headlineLarge: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.20,
        color: AppTokens.ink),
    headlineMedium: TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.65,
        height: 1.22,
        color: AppTokens.ink),
    headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
        height: 1.24,
        color: AppTokens.ink),
    titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        height: 1.25,
        color: AppTokens.ink),
    titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.18,
        height: 1.30,
        color: AppTokens.ink),
    titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: AppTokens.ink),
    bodyLarge: TextStyle(fontSize: 16, height: 1.40, color: AppTokens.ink),
    bodyMedium: TextStyle(fontSize: 15, height: 1.40, color: AppTokens.ink),
    bodySmall: TextStyle(fontSize: 13, height: 1.40, color: AppTokens.muted),
    labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.30,
        color: AppTokens.ink),
    labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.28,
        color: AppTokens.muted),
    labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        height: 1.28,
        color: AppTokens.muted),
  );

  static final ThemeData lightTheme = _buildTheme();

  static ThemeData _buildTheme() {
    const buttonText = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    const buttonSize = Size(44, 46);
    const pill = StadiumBorder();
    const border = BorderSide(color: AppTokens.outline);
    const cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppTokens.cardRadius)),
      side: border,
    );
    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
      borderSide: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppTokens.canvas,
      textTheme: textTheme,
      colorScheme: const ColorScheme.light(
        primary: BrandColors.kakaGreen,
        onPrimary: AppTokens.ink,
        primaryContainer: BrandColors.greenLightest,
        onPrimaryContainer: BrandColors.greenDarker,
        secondary: BrandColors.kakaBlue,
        onSecondary: AppTokens.ink,
        secondaryContainer: BrandColors.blueLightest,
        onSecondaryContainer: BrandColors.blueDarker,
        tertiary: BrandColors.kakaPink,
        onTertiary: Colors.black,
        tertiaryContainer: BrandColors.pinkLightest,
        onTertiaryContainer: BrandColors.pinkDarker,
        error: BrandColors.pinkDarker,
        onError: Colors.white,
        errorContainer: BrandColors.pinkLightest,
        onErrorContainer: BrandColors.pinkDarker,
        surface: AppTokens.surface,
        onSurface: AppTokens.ink,
        onSurfaceVariant: AppTokens.muted,
        surfaceContainerLowest: AppTokens.surface,
        surfaceContainerLow: AppTokens.canvas,
        surfaceContainer: AppTokens.surfaceQuiet,
        outline: AppTokens.muted,
        outlineVariant: AppTokens.outline,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppTokens.gutter,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.55,
          color: AppTokens.ink,
        ),
        iconTheme: IconThemeData(color: AppTokens.ink, size: 22),
        actionsIconTheme: IconThemeData(color: AppTokens.ink, size: 21),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: AppTokens.ink,
          backgroundColor: BrandColors.kakaBlue,
          minimumSize: buttonSize,
          elevation: 0,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.ink,
          minimumSize: buttonSize,
          side: border,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.blueDarker,
          minimumSize: buttonSize,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppTokens.ink,
          minimumSize: const Size.square(44),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: const WidgetStatePropertyAll(pill),
          side: const WidgetStatePropertyAll(border),
          textStyle: const WidgetStatePropertyAll(buttonText),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? BrandColors.blueLightest
                : AppTokens.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? BrandColors.blueDarker
                : AppTokens.muted,
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppTokens.surfaceQuiet,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
          borderSide: BorderSide(color: BrandColors.blueDark, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: TextStyle(color: AppTokens.muted),
        hintStyle: TextStyle(color: AppTokens.muted),
      ),
      dividerTheme: const DividerThemeData(
          color: AppTokens.outline, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: BrandColors.blueLightest,
        indicatorShape: pill,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            height: 1.1,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppTokens.ink
                : AppTokens.muted,
          ),
        ),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 22)),
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: AppTokens.outline,
        labelColor: BrandColors.blueDarker,
        unselectedLabelColor: AppTokens.muted,
        indicatorColor: BrandColors.kakaBlue,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppTokens.ink,
        contentTextStyle: TextStyle(fontSize: 14, color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      dialogTheme: const DialogThemeData(
        elevation: 0,
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        titleTextStyle: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.45,
          color: AppTokens.ink,
        ),
        contentTextStyle:
            TextStyle(fontSize: 15, color: AppTokens.ink, height: 1.4),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        dragHandleColor: AppTokens.outline,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        minLeadingWidth: 40,
        iconColor: AppTokens.muted,
        textColor: AppTokens.ink,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BrandColors.greenDarker
              : AppTokens.outline,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BrandColors.kakaBlue,
        foregroundColor: AppTokens.ink,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppTokens.surfaceQuiet,
        selectedColor: BrandColors.blueLightest,
        side: BorderSide.none,
        shape: pill,
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: BrandColors.kakaBlue,
        textColor: AppTokens.ink,
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        primaryColor: BrandColors.blueDarker,
        barBackgroundColor: AppTokens.canvas,
        scaffoldBackgroundColor: AppTokens.canvas,
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme;
}
