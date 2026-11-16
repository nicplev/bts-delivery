import 'package:flutter/material.dart';

/// KAKA Brand Colors
/// Official brand colors for the BTS Delivery App
class BrandColors {
  BrandColors._(); // Private constructor to prevent instantiation

  // ========== PRIMARY BRAND COLORS ==========

  /// KAKA Green - Primary brand color
  /// Hex: #2bb673
  static const Color kakaGreen = Color(0xFF2bb673);

  /// KAKA Blue - Secondary brand color
  /// Hex: #00aeef
  static const Color kakaBlue = Color(0xFF00aeef);

  /// KAKA Pink - Accent brand color
  /// Hex: #ec008c
  static const Color kakaPink = Color(0xFFec008c);

  /// KAKA Yellow - Highlight brand color
  /// Hex: #f9ed32
  static const Color kakaYellow = Color(0xFFf9ed32);

  // ========== GREEN SHADES ==========

  static const Color greenLight = Color(0xFF5FD497);
  static const Color greenLighter = Color(0xFF93E2BB);
  static const Color greenLightest = Color(0xFFE8F7F0);
  static const Color greenDark = Color(0xFF229959);
  static const Color greenDarker = Color(0xFF1A7C46);

  // ========== BLUE SHADES ==========

  static const Color blueLight = Color(0xFF33BEF3);
  static const Color blueLighter = Color(0xFF80D7F8);
  static const Color blueLightest = Color(0xFFE6F7FD);
  static const Color blueDark = Color(0xFF008BBF);
  static const Color blueDarker = Color(0xFF006A8F);

  // ========== PINK SHADES ==========

  static const Color pinkLight = Color(0xFFF033A6);
  static const Color pinkLighter = Color(0xFFF580C6);
  static const Color pinkLightest = Color(0xFFFDE6F3);
  static const Color pinkDark = Color(0xFFBC0070);
  static const Color pinkDarker = Color(0xFF8D0055);

  // ========== YELLOW SHADES ==========

  static const Color yellowLight = Color(0xFFFBF25B);
  static const Color yellowLighter = Color(0xFFFDF79B);
  static const Color yellowLightest = Color(0xFFFEFCE8);
  static const Color yellowDark = Color(0xFFC7BE28);
  static const Color yellowDarker = Color(0xFF958E1E);

  // ========== NEUTRAL COLORS ==========

  /// Pure black for text and icons
  static const Color black = Color(0xFF000000);

  /// Pure white for backgrounds
  static const Color white = Color(0xFFFFFFFF);

  /// iOS-style grays
  static const Color gray1 = Color(0xFF1C1C1E); // Almost black
  static const Color gray2 = Color(0xFF2C2C2E); // Very dark gray
  static const Color gray3 = Color(0xFF3A3A3C); // Dark gray
  static const Color gray4 = Color(0xFF48484A); // Medium dark gray
  static const Color gray5 = Color(0xFF636366); // Medium gray
  static const Color gray6 = Color(0xFF8E8E93); // Light medium gray
  static const Color gray7 = Color(0xFFC7C7CC); // Light gray
  static const Color gray8 = Color(0xFFD1D1D6); // Very light gray
  static const Color gray9 = Color(0xFFE5E5EA); // Almost white gray
  static const Color gray10 = Color(0xFFF2F2F7); // Background gray

  // ========== SEMANTIC COLORS ==========

  /// Success states
  static const Color success = kakaGreen;
  static const Color successLight = greenLightest;

  /// Info states
  static const Color info = kakaBlue;
  static const Color infoLight = blueLightest;

  /// Warning states
  static const Color warning = kakaYellow;
  static const Color warningLight = yellowLightest;

  /// Error states
  static const Color error = kakaPink;
  static const Color errorLight = pinkLightest;

  // ========== SURFACE COLORS ==========

  /// iOS-style surface colors
  static const Color surfacePrimary = white;
  static const Color surfaceSecondary = gray10;
  static const Color surfaceTertiary = gray9;

  /// Card backgrounds
  static const Color cardBackground = white;
  static const Color cardElevated = white;

  /// Dividers and borders
  static const Color divider = gray8;
  static const Color border = gray7;

  // ========== TEXT COLORS ==========

  static const Color textPrimary = black;
  static const Color textSecondary = gray2;
  static const Color textTertiary = gray5;
  static const Color textDisabled = gray6;
  static const Color textOnColor = white;

  // ========== HELPER METHODS ==========

  /// Get color with opacity
  static Color withOpacity(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }

  /// Get subtle background variant of brand color
  static Color getSubtleBackground(Color brandColor) {
    return brandColor.withValues(alpha: 0.08);
  }

  /// Get light variant of brand color
  static Color getLightVariant(Color brandColor) {
    return brandColor.withValues(alpha: 0.15);
  }
}
