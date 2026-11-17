import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Neutral Material theme built from [AppPalette] (four variants).
class AppTheme {
  AppTheme._();

  static const _type = TextTheme(
    displayLarge:
        TextStyle(fontSize: 40, fontWeight: FontWeight.w700, height: 1.14),
    displayMedium: AppTypography.largeTitle,
    displaySmall:
        TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 34 / 28),
    headlineLarge:
        TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2),
    headlineMedium:
        TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
    headlineSmall: AppTypography.title2,
    titleLarge:
        TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 25 / 20),
    titleMedium: AppTypography.headline,
    titleSmall:
        TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 20 / 15),
    bodyLarge: AppTypography.body,
    bodyMedium: AppTypography.body,
    bodySmall: AppTypography.subheadline,
    labelLarge:
        TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 22 / 17),
    labelMedium:
        TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 20 / 15),
    labelSmall:
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 18 / 13),
  );

  static final ThemeData lightTheme = _buildTheme(const AppPalette());
  static final ThemeData darkTheme = _buildTheme(const AppPalette(dark: true));
  static final ThemeData highContrastLightTheme =
      _buildTheme(const AppPalette(highContrast: true));
  static final ThemeData highContrastDarkTheme =
      _buildTheme(const AppPalette(dark: true, highContrast: true));

  static ThemeData _buildTheme(AppPalette colors) {
    const buttonText = TextStyle(
        fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.43);
    const buttonSize = Size(44, 44);
    const primarySize = Size(44, AppTokens.primaryButtonHeight);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 10);
    final text = _type.apply(bodyColor: colors.ink, displayColor: colors.ink);
    final textTheme = text.copyWith(
      bodySmall: text.bodySmall?.copyWith(color: colors.muted),
      labelMedium: text.labelMedium?.copyWith(color: colors.muted),
      labelSmall: text.labelSmall?.copyWith(color: colors.muted),
    );
    const pill = StadiumBorder();
    // Content is borderless in normal contrast; high contrast keeps outlines.
    final contentSide = colors.highContrast
        ? BorderSide(color: colors.outline)
        : BorderSide.none;
    final cardShape = RoundedRectangleBorder(
      borderRadius:
          const BorderRadius.all(Radius.circular(AppTokens.cardRadius)),
      side: contentSide,
    );
    const inputRadius =
        BorderRadius.all(Radius.circular(AppTokens.controlRadius));
    final inputBorder =
        OutlineInputBorder(borderRadius: inputRadius, borderSide: contentSide);
    final disabledFill = colors.surfaceQuiet;
    final disabledInk = colors.muted;

    final primaryStyle = FilledButton.styleFrom(
      backgroundColor: colors.action,
      foregroundColor: colors.onAction,
      disabledBackgroundColor: disabledFill,
      disabledForegroundColor: disabledInk,
      minimumSize: primarySize,
      elevation: 0,
      shape: pill,
      padding: buttonPadding,
      textStyle: buttonText,
    );
    // A disabled secondary button keeps the enabled grey fill and fades its
    // label, so it never looks stronger than an enabled one.
    final secondaryDisabledInk =
        colors.ink.withValues(alpha: colors.highContrast ? 0.55 : 0.35);
    final secondaryStyle = TextButton.styleFrom(
      backgroundColor: colors.fill,
      foregroundColor: colors.ink,
      disabledBackgroundColor: colors.fill,
      disabledForegroundColor: secondaryDisabledInk,
      minimumSize: buttonSize,
      elevation: 0,
      shape: pill,
      side: colors.highContrast ? BorderSide(color: colors.outline) : null,
      padding: buttonPadding,
      textStyle: buttonText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      extensions: [colors],
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.fill,
      colorScheme: ColorScheme(
        brightness: colors.brightness,
        primary: colors.action,
        onPrimary: colors.onAction,
        primaryContainer: colors.surfaceQuiet,
        onPrimaryContainer: colors.ink,
        secondary: colors.muted,
        onSecondary: colors.surface,
        secondaryContainer: colors.surfaceQuiet,
        onSecondaryContainer: colors.ink,
        tertiary: colors.ink,
        onTertiary: colors.canvas,
        tertiaryContainer: colors.surfaceQuiet,
        onTertiaryContainer: colors.ink,
        error: colors.error,
        onError: colors.onError,
        errorContainer: colors.errorContainer,
        onErrorContainer: colors.error,
        surface: colors.surface,
        onSurface: colors.ink,
        onSurfaceVariant: colors.muted,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: colors.surface,
        surfaceContainerLow: colors.canvas,
        surfaceContainer: colors.surfaceQuiet,
        surfaceContainerHigh: colors.surfaceQuiet,
        surfaceContainerHighest: colors.surfaceQuiet,
        inverseSurface: colors.ink,
        onInverseSurface: colors.canvas,
        inversePrimary: colors.canvas,
        outline: colors.muted,
        outlineVariant: colors.outline,
        scrim: colors.scrim,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppTokens.gutter,
        titleTextStyle: AppTypography.headline.copyWith(color: colors.ink),
        iconTheme: IconThemeData(color: colors.ink, size: 22),
        actionsIconTheme: IconThemeData(color: colors.ink, size: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: cardShape,
        margin: const EdgeInsets.symmetric(
            horizontal: AppTokens.gutter, vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(style: primaryStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.action,
          foregroundColor: colors.onAction,
          disabledBackgroundColor: disabledFill,
          disabledForegroundColor: disabledInk,
          minimumSize: primarySize,
          elevation: 0,
          shape: pill,
          padding: buttonPadding,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: colors.fill,
          foregroundColor: colors.ink,
          disabledBackgroundColor: colors.fill,
          disabledForegroundColor: secondaryDisabledInk,
          minimumSize: buttonSize,
          side: colors.highContrast
              ? BorderSide(color: colors.outline)
              : BorderSide.none,
          shape: pill,
          padding: buttonPadding,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: secondaryStyle),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.ink,
          minimumSize: const Size.square(AppTokens.minTouchTarget),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: const WidgetStatePropertyAll(pill),
          // iOS-style: grey track, the selected segment is a white capsule
          // (a lighter grey than the track in dark themes).
          side: WidgetStatePropertyAll(BorderSide(
            color: colors.highContrast ? colors.outline : colors.surfaceQuiet,
            width: 2,
          )),
          textStyle: const WidgetStatePropertyAll(TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.23)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.segmentThumb
                : colors.surfaceQuiet,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.muted
                : colors.ink,
          ),
          iconColor: WidgetStatePropertyAll(colors.ink),
          overlayColor: WidgetStatePropertyAll(colors.fill),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceQuiet,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: colors.ink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: TextStyle(color: colors.muted),
        floatingLabelStyle: TextStyle(color: colors.ink),
        hintStyle: TextStyle(color: colors.muted),
        prefixIconColor: colors.muted,
        suffixIconColor: colors.muted,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.ink,
        selectionColor: colors.ink.withValues(alpha: 0.2),
        selectionHandleColor: colors.ink,
      ),
      dividerTheme:
          DividerThemeData(color: colors.separator, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.ink,
        linearTrackColor: colors.surfaceQuiet,
        circularTrackColor: Colors.transparent,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) &&
                    !states.contains(WidgetState.disabled)
                ? colors.action
                : null),
        checkColor: WidgetStatePropertyAll(colors.onAction),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? colors.action
                : colors.muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppTokens.tabBarHeight,
        elevation: 0,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.surfaceQuiet,
        indicatorShape: pill,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTypography.tabLabel.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.ink
                : colors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? colors.ink
                : colors.muted)),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: colors.separator,
        labelColor: colors.ink,
        unselectedLabelColor: colors.muted,
        indicatorColor: colors.ink,
        overlayColor: WidgetStatePropertyAll(colors.fill),
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: TextStyle(fontSize: 15, color: colors.canvas),
        actionTextColor: colors.canvas,
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
        titleTextStyle: AppTypography.title3.copyWith(color: colors.ink),
        contentTextStyle: AppTypography.body.copyWith(color: colors.ink),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: colors.scrim,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: contentSide,
        ),
        dragHandleColor: colors.inactive,
        dragHandleSize: const Size(36, 5),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        textStyle: AppTypography.body.copyWith(color: colors.ink),
        shape: RoundedRectangleBorder(
          borderRadius:
              const BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
          side: contentSide,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 29,
        iconColor: colors.ink,
        textColor: colors.ink,
        selectedColor: colors.ink,
        selectedTileColor: colors.fill,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) &&
                    !states.contains(WidgetState.disabled)
                ? colors.onAction
                : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) &&
                    !states.contains(WidgetState.disabled)
                ? colors.action
                : null),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? colors.action : null),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.action,
        foregroundColor: colors.onAction,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: pill,
      ),
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? colors.action
                : colors.surfaceQuiet),
        labelStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? colors.onAction
                  : colors.ink),
        ),
        checkmarkColor: colors.onAction,
        iconTheme: IconThemeData(color: colors.ink, size: 18),
        side: colors.highContrast
            ? BorderSide(color: colors.outline)
            : BorderSide.none,
        shape: pill,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: colors.action,
        textColor: colors.onAction,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.ink,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(fontSize: 13, color: colors.canvas),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: colors.brightness,
        primaryColor: colors.ink,
        primaryContrastingColor: colors.onAction,
        barBackgroundColor: colors.glassFill,
        scaffoldBackgroundColor: colors.canvas,
      ),
    );
  }
}
