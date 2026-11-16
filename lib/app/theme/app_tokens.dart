import 'package:flutter/material.dart';

import 'brand_colors.dart';

class AppTokens {
  AppTokens._();

  static const canvas = Color(0xFFF2F6F8);
  static const surface = Colors.white;
  static const surfaceQuiet = Color(0xFFEDF3F6);
  static const outline = Color(0xFFDFE8ED);
  static const ink = Color(0xFF14242C);
  static const muted = Color(0xFF536570);

  static const gutter = 20.0;
  static const sectionGap = 24.0;
  static const cardRadius = 22.0;
  static const controlRadius = 14.0;
  static const pillRadius = 999.0;
  static const panelShadow = [
    BoxShadow(color: Color(0x0A243C48), blurRadius: 16, offset: Offset(0, 5)),
  ];
}

enum AppTone {
  neutral,
  green,
  blue,
  pink,
  yellow;

  Color get accent => switch (this) {
        neutral => AppTokens.muted,
        green => BrandColors.kakaGreen,
        blue => BrandColors.kakaBlue,
        pink => BrandColors.kakaPink,
        yellow => BrandColors.kakaYellow,
      };

  Color get tint => switch (this) {
        neutral => AppTokens.surfaceQuiet,
        green => BrandColors.greenLightest,
        blue => BrandColors.blueLightest,
        pink => BrandColors.pinkLightest,
        yellow => BrandColors.yellowLightest,
      };

  Color get ink => switch (this) {
        neutral => AppTokens.muted,
        green => BrandColors.greenDarker,
        blue => BrandColors.blueDarker,
        pink => BrandColors.pinkDarker,
        yellow => const Color(0xFF665A08),
      };
}
