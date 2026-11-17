import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'brand_colors.dart';

class AppTheme {
  AppTheme._();

  static const _type = TextTheme(
    displayLarge:
        TextStyle(fontSize: 40, fontWeight: FontWeight.w600, height: 1.14),
    displayMedium:
        TextStyle(fontSize: 34, fontWeight: FontWeight.w600, height: 1.16),
    displaySmall:
        TextStyle(fontSize: 29, fontWeight: FontWeight.w600, height: 1.18),
    headlineLarge:
        TextStyle(fontSize: 26, fontWeight: FontWeight.w600, height: 1.20),
    headlineMedium:
        TextStyle(fontSize: 23, fontWeight: FontWeight.w600, height: 1.22),
    headlineSmall:
        TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.24),
    titleLarge:
        TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.26),
    titleMedium:
        TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.30),
    titleSmall:
        TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.32),
    bodyLarge: TextStyle(fontSize: 17, height: 1.36),
    bodyMedium: TextStyle(fontSize: 17, height: 1.36),
    bodySmall: TextStyle(fontSize: 15, height: 1.36),
    labelLarge:
        TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.30),
    labelMedium:
        TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.28),
    labelSmall:
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.28),
  );

  static final ThemeData lightTheme = _buildTheme(const AppPalette());
  static final ThemeData darkTheme = _buildTheme(const AppPalette(dark: true));
  static final ThemeData highContrastLightTheme =
      _buildTheme(const AppPalette(highContrast: true));
  static final ThemeData highContrastDarkTheme =
      _buildTheme(const AppPalette(dark: true, highContrast: true));

  static ThemeData _buildTheme(AppPalette colors) {
    const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    const buttonSize = Size(44, 48);
    final text = _type.apply(bodyColor: colors.ink, displayColor: colors.ink);
    final textTheme = text.copyWith(
      bodySmall: text.bodySmall?.copyWith(color: colors.muted),
      labelMedium: text.labelMedium?.copyWith(color: colors.muted),
      labelSmall: text.labelSmall?.copyWith(color: colors.muted),
    );
    final greenInk = AppTone.green.inkOn(colors);
    final blueInk = AppTone.blue.inkOn(colors);
    final pinkInk = AppTone.pink.inkOn(colors);
    final greenTint = AppTone.green.tintOn(colors);
    final blueTint = AppTone.blue.tintOn(colors);
    final pinkTint = AppTone.pink.tintOn(colors);
    const pill = StadiumBorder();
    final border = BorderSide(color: colors.outline);
    final cardShape = RoundedRectangleBorder(
      borderRadius:
          const BorderRadius.all(Radius.circular(AppTokens.cardRadius)),
      side: border,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius:
          const BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
      borderSide: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      extensions: [colors],
      scaffoldBackgroundColor: colors.canvas,
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: colors.brightness,
        primary: BrandColors.kakaGreen,
        onPrimary: colors.actionInk,
        primaryContainer: greenTint,
        onPrimaryContainer: greenInk,
        secondary: BrandColors.kakaBlue,
        onSecondary: colors.actionInk,
        secondaryContainer: blueTint,
        onSecondaryContainer: blueInk,
        tertiary: BrandColors.kakaPink,
        onTertiary: Colors.black,
        tertiaryContainer: pinkTint,
        onTertiaryContainer: pinkInk,
        error: colors.error,
        onError: colors.onError,
        errorContainer: colors.errorContainer,
        onErrorContainer: colors.error,
        surface: colors.surface,
        onSurface: colors.ink,
        onSurfaceVariant: colors.muted,
        surfaceContainerLowest: colors.surface,
        surfaceContainerLow: colors.canvas,
        surfaceContainer: colors.surfaceQuiet,
        outline: colors.muted,
        outlineVariant: colors.outline,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppTokens.gutter,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colors.ink,
        ),
        iconTheme: IconThemeData(color: colors.ink, size: 22),
        actionsIconTheme: IconThemeData(color: colors.ink, size: 21),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: colors.actionInk,
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
          foregroundColor: colors.ink,
          minimumSize: buttonSize,
          side: border,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blueInk,
          minimumSize: buttonSize,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.ink,
          minimumSize: const Size.square(44),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: const WidgetStatePropertyAll(pill),
          side: WidgetStatePropertyAll(border),
          textStyle: const WidgetStatePropertyAll(buttonText),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? blueTint
                : colors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? blueInk : colors.muted,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceQuiet,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius:
              const BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
          borderSide: BorderSide(color: blueInk, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: TextStyle(color: colors.muted),
        hintStyle: TextStyle(color: colors.muted),
      ),
      dividerTheme:
          DividerThemeData(color: colors.outline, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: blueTint,
        indicatorShape: pill,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            height: 1.1,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colors.ink
                : colors.muted,
          ),
        ),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 22)),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: colors.outline,
        labelColor: blueInk,
        unselectedLabelColor: colors.muted,
        indicatorColor: BrandColors.kakaBlue,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: TextStyle(fontSize: 16, color: colors.canvas),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        titleTextStyle: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: colors.ink,
        ),
        contentTextStyle:
            TextStyle(fontSize: 17, color: colors.ink, height: 1.36),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        dragHandleColor: colors.outline,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        minLeadingWidth: 40,
        iconColor: colors.muted,
        textColor: colors.ink,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) &&
                    !states.contains(WidgetState.disabled)
                ? colors.actionInk
                : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) &&
                    !states.contains(WidgetState.disabled)
                ? BrandColors.kakaGreen
                : null),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: BrandColors.kakaBlue,
        foregroundColor: colors.actionInk,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceQuiet,
        selectedColor: blueTint,
        side: BorderSide.none,
        shape: pill,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: BrandColors.kakaBlue,
        textColor: colors.actionInk,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: colors.brightness,
        primaryColor: blueInk,
        barBackgroundColor: colors.canvas,
        scaffoldBackgroundColor: colors.canvas,
      ),
    );
  }
}
