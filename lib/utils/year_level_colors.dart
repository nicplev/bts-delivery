import 'package:flutter/material.dart';

import '../app/theme/app_tokens.dart';

class YearLevelColors {
  static Color getBackgroundColor(BuildContext context, String label) {
    final colors = AppPalette.of(context);
    final name = label.toLowerCase();
    if (needsBorder(name)) return colors.surface;
    if (name.contains('specialist')) return colors.surfaceQuiet;
    return _tone(name).tintOn(colors);
  }

  static Color getIconColor(BuildContext context, String label) {
    final colors = AppPalette.of(context);
    final name = label.toLowerCase();
    if (needsBorder(name) || name.contains('specialist')) return colors.ink;
    return _tone(name).inkOn(colors);
  }

  static AppTone _tone(String name) => switch (_yearNumber(name)) {
        1 || 4 => AppTone.pink,
        2 => AppTone.blue,
        5 || 6 => AppTone.yellow,
        _ => AppTone.green,
      };

  static int? _yearNumber(String name) {
    final match = RegExp(r'\b(?:year|grade)\s*([1-6])\b').firstMatch(name);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool needsBorder(String label) {
    final name = label.toLowerCase();
    return name.contains('prep') || name.contains('foundation');
  }
}
