import 'package:flutter/material.dart';

import 'brand_colors.dart';

class AppTokens {
  AppTokens._();

  static const gutter = 20.0;
  static const sectionGap = 24.0;
  static const cardRadius = 16.0;
  static const controlRadius = 12.0;
  static const pillRadius = 999.0;
  static const panelShadow = [
    BoxShadow(color: Color(0x16000000), blurRadius: 16, offset: Offset(0, 5)),
  ];
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({this.dark = false, this.highContrast = false});

  final bool dark;
  final bool highContrast;

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPalette>() ??
        AppPalette(
          dark: theme.brightness == Brightness.dark,
          highContrast: MediaQuery.maybeHighContrastOf(context) ?? false,
        );
  }

  Brightness get brightness => dark ? Brightness.dark : Brightness.light;
  Color get canvas => dark ? const Color(0xFF11161C) : const Color(0xFFF3F5F7);
  Color get surface => dark ? const Color(0xFF20272E) : Colors.white;
  Color get surfaceQuiet =>
      dark ? const Color(0xFF2A333B) : const Color(0xFFEDF1F5);

  Color get outline => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFF8897A5),
        (true, false) => const Color(0xFF394552),
        (false, true) => const Color(0xFF687683),
        (false, false) => const Color(0xFFDCE2E8),
      };

  Color get ink => switch ((dark, highContrast)) {
        (true, true) => Colors.white,
        (true, false) => const Color(0xFFF5F7FA),
        (false, true) => const Color(0xFF0B1218),
        (false, false) => const Color(0xFF18212A),
      };

  Color get muted => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFFE0E7EE),
        (true, false) => const Color(0xFFB7C1CB),
        (false, true) => const Color(0xFF283440),
        (false, false) => const Color(0xFF4B5965),
      };

  Color get actionInk => const Color(0xFF0B1611);
  Color get error => dark ? const Color(0xFFFFAAB4) : const Color(0xFF9D2236);
  Color get onError => dark ? const Color(0xFF30040B) : Colors.white;
  Color get errorContainer =>
      dark ? const Color(0xFF502730) : const Color(0xFFFFE7EA);

  @override
  AppPalette copyWith({bool? dark, bool? highContrast}) => AppPalette(
        dark: dark ?? this.dark,
        highContrast: highContrast ?? this.highContrast,
      );

  @override
  AppPalette lerp(AppPalette? other, double t) =>
      t < 0.5 ? this : other ?? this;
}

enum AppTone {
  neutral,
  green,
  blue,
  pink,
  yellow;

  Color get accent => switch (this) {
        neutral => const AppPalette().muted,
        green => BrandColors.kakaGreen,
        blue => BrandColors.kakaBlue,
        pink => BrandColors.kakaPink,
        yellow => BrandColors.kakaYellow,
      };

  Color inkFor(BuildContext context) => inkOn(AppPalette.of(context));
  Color tintFor(BuildContext context) => tintOn(AppPalette.of(context));

  Color tintOn(AppPalette colors) => switch ((this, colors.dark)) {
        (neutral, _) => colors.surfaceQuiet,
        (green, true) => const Color(0xFF19392C),
        (blue, true) => const Color(0xFF163449),
        (pink, true) => const Color(0xFF482438),
        (yellow, true) => const Color(0xFF37351C),
        (green, false) => BrandColors.greenLightest,
        (blue, false) => BrandColors.blueLightest,
        (pink, false) => BrandColors.pinkLightest,
        (yellow, false) => colors.highContrast
            ? const Color(0xFFFFF2A3)
            : BrandColors.yellowLightest,
      };

  Color inkOn(AppPalette colors) {
    if (this == neutral) return colors.muted;
    return switch ((this, colors.dark, colors.highContrast)) {
      (green, true, true) => const Color(0xFFB6F8D9),
      (blue, true, true) => const Color(0xFFBDEEFF),
      (pink, true, true) => const Color(0xFFFFCDE9),
      (yellow, true, true) => const Color(0xFFFFFAC0),
      (green, true, false) => BrandColors.greenLighter,
      (blue, true, false) => BrandColors.blueLighter,
      (pink, true, false) => const Color(0xFFFFA8D8),
      (yellow, true, false) => const Color(0xFFFFF39A),
      (green, false, true) => const Color(0xFF064A2B),
      (blue, false, true) => const Color(0xFF003E5B),
      (pink, false, true) => const Color(0xFF68053C),
      (yellow, false, true) => const Color(0xFF382C00),
      (green, false, false) => BrandColors.greenDarker,
      (blue, false, false) => const Color(0xFF005980),
      (pink, false, false) => BrandColors.pinkDarker,
      (yellow, false, false) => const Color(0xFF695300),
      _ => colors.muted,
    };
  }
}
