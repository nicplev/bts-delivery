import 'package:flutter/material.dart';

import '../app/theme/app_tokens.dart';
import '../app/theme/brand_colors.dart';

class YearLevelColors {
  static Color getBackgroundColor(String label) {
    final name = label.toLowerCase();
    if (needsBorder(name)) return AppTokens.surface;
    if (name.contains('specialist')) return AppTokens.surfaceQuiet;

    return switch (_yearNumber(name)) {
      1 => BrandColors.pinkLightest,
      2 => BrandColors.blueLightest,
      3 => BrandColors.greenLightest,
      4 => BrandColors.pinkLighter,
      5 => BrandColors.yellowLightest,
      6 => BrandColors.yellowLighter,
      _ => BrandColors.greenLightest,
    };
  }

  static Color getIconColor(String label) {
    final name = label.toLowerCase();
    if (needsBorder(name) || name.contains('specialist')) return AppTokens.ink;
    return switch (_yearNumber(name)) {
      1 || 4 => AppTone.pink.ink,
      2 => AppTone.blue.ink,
      5 || 6 => AppTone.yellow.ink,
      _ => AppTone.green.ink,
    };
  }

  static int? _yearNumber(String name) {
    final match = RegExp(r'\b(?:year|grade)\s*([1-6])\b').firstMatch(name);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool needsBorder(String label) {
    final name = label.toLowerCase();
    return name.contains('prep') || name.contains('foundation');
  }
}
