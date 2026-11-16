import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'brand_colors.dart';

/// Apple-inspired theme configuration for BTS Delivery App
class AppTheme {
  AppTheme._(); // Private constructor

  // ========== TEXT THEME ==========

  static const TextTheme textTheme = TextTheme(
    // Display styles - Large headings
    displayLarge: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.5,
      color: BrandColors.textPrimary,
      height: 1.2,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.3,
      color: BrandColors.textPrimary,
      height: 1.25,
    ),
    displaySmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.2,
      color: BrandColors.textPrimary,
      height: 1.3,
    ),

    // Headline styles - Section headers
    headlineLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: BrandColors.textPrimary,
      height: 1.3,
    ),
    headlineMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: BrandColors.textPrimary,
      height: 1.35,
    ),
    headlineSmall: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: BrandColors.textPrimary,
      height: 1.4,
    ),

    // Title styles - Card titles
    titleLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: BrandColors.textPrimary,
      height: 1.35,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: BrandColors.textPrimary,
      height: 1.4,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: BrandColors.textPrimary,
      height: 1.45,
    ),

    // Body styles - Regular text
    bodyLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.4,
      color: BrandColors.textPrimary,
      height: 1.35,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.2,
      color: BrandColors.textPrimary,
      height: 1.4,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.1,
      color: BrandColors.textSecondary,
      height: 1.45,
    ),

    // Label styles - Small text, captions
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.2,
      color: BrandColors.textPrimary,
      height: 1.4,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      color: BrandColors.textSecondary,
      height: 1.45,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: BrandColors.textTertiary,
      height: 1.5,
    ),
  );

  // ========== LIGHT THEME ==========

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color scheme
      colorScheme: const ColorScheme.light(
        primary: BrandColors.kakaGreen,
        onPrimary: BrandColors.white,
        secondary: BrandColors.kakaBlue,
        onSecondary: BrandColors.white,
        tertiary: BrandColors.kakaPink,
        onTertiary: BrandColors.white,
        error: BrandColors.kakaPink,
        onError: BrandColors.white,
        surface: BrandColors.surfacePrimary,
        onSurface: BrandColors.textPrimary,
      ),

      // Scaffold
      scaffoldBackgroundColor: BrandColors.surfaceSecondary,

      // App Bar theme (iOS-style)
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: BrandColors.surfacePrimary,
        foregroundColor: BrandColors.textPrimary,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: BrandColors.textPrimary,
        ),
        iconTheme: IconThemeData(
          color: BrandColors.kakaBlue, // Blue for app bar icons
          size: 24,
        ),
      ),

      // Card theme (iOS-style rounded cards)
      cardTheme: const CardThemeData(
        elevation: 0,
        color: BrandColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Button themes - Using variety of KAKA colors
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: BrandColors.kakaBlue, // Blue for primary actions
          foregroundColor: BrandColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: BrandColors.kakaGreen, // Green for filled buttons
          foregroundColor: BrandColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: BrandColors.kakaPink, // Pink for outlined buttons
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(
            color: BrandColors.kakaPink,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.kakaBlue, // Blue for text buttons
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.4,
          ),
        ),
      ),

      // Icon button theme
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: BrandColors.kakaBlue, // Blue for icon buttons
          padding: const EdgeInsets.all(12),
        ),
      ),

      // Input decoration theme (iOS-style inputs)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BrandColors.surfaceSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: BrandColors.kakaBlue, // Blue for focused inputs
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: BrandColors.kakaPink,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.2,
          color: BrandColors.textTertiary,
        ),
        hintStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.2,
          color: BrandColors.textDisabled,
        ),
      ),

      // Divider theme
      dividerTheme: const DividerThemeData(
        color: BrandColors.divider,
        thickness: 0.5,
        space: 1,
      ),

      // Navigation bar theme (bottom nav) - Colors handled per-item in app_shell.dart
      navigationBarTheme: NavigationBarThemeData(
        height: 65,
        elevation: 0,
        backgroundColor: BrandColors.surfacePrimary,
        indicatorColor: Colors.transparent, // No background indicator - icons carry the color
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: BrandColors.textPrimary, // Label color handled per-item
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: BrandColors.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              size: 26,
            );
          }
          return const IconThemeData(
            size: 24,
          );
        }),
      ),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BrandColors.gray2,
        contentTextStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.2,
          color: BrandColors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // Dialog theme
      dialogTheme: const DialogThemeData(
        elevation: 0,
        backgroundColor: BrandColors.surfacePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: BrandColors.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.2,
          color: BrandColors.textSecondary,
        ),
      ),

      // List tile theme
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 40,
        iconColor: BrandColors.textSecondary,
        textColor: BrandColors.textPrimary,
      ),

      // Switch theme (iOS-style)
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(BrandColors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BrandColors.kakaGreen;
          }
          return BrandColors.gray7;
        }),
      ),

      // Floating Action Button - Yellow accent
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BrandColors.kakaBlue,
        foregroundColor: BrandColors.gray1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      // Chip theme - Using variety of colors
      chipTheme: ChipThemeData(
        backgroundColor: BrandColors.getSubtleBackground(BrandColors.kakaBlue),
        deleteIconColor: BrandColors.kakaBlue,
        selectedColor: BrandColors.kakaBlue,
        secondarySelectedColor: BrandColors.kakaPink,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // Badge theme - Yellow for notifications
      badgeTheme: const BadgeThemeData(
        backgroundColor: BrandColors.kakaBlue,
        textColor: BrandColors.gray1,
        textStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Text theme
      textTheme: textTheme,

      // iOS-specific
      cupertinoOverrideTheme: const CupertinoThemeData(
        primaryColor: BrandColors.kakaGreen,
        barBackgroundColor: BrandColors.surfacePrimary,
        scaffoldBackgroundColor: BrandColors.surfaceSecondary,
      ),
    );
  }

  // ========== DARK THEME ==========
  // For now, using the same light theme - dark theme can be customized later
  static ThemeData get darkTheme => lightTheme;
}
