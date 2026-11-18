import 'package:flutter/material.dart';

/// Spacing, radii and sizes shared by every screen (390 × 844 pt reference).
class AppTokens {
  AppTokens._();

  /// Horizontal screen gutter.
  static const gutter = 16.0;

  /// Vertical gap between sections of a screen.
  static const sectionGap = 24.0;

  /// Card / panel / grouped list corner radius.
  static const cardRadius = 20.0;

  /// Inner tiles, notices, inputs and other controls.
  static const controlRadius = 12.0;

  /// Capsules (pills, buttons, tab bar).
  static const pillRadius = 999.0;

  /// Bottom corners of the year-coloured classroom header.
  static const headerRadius = 28.0;

  /// Glass modal sheet corner radius.
  static const sheetRadius = 36.0;

  /// Inset of a glass modal sheet from the screen edges.
  static const sheetInset = 8.0;

  /// Minimum touch target.
  static const minTouchTarget = 44.0;

  /// Glass navigation button (back / options) diameter.
  static const navButtonSize = 44.0;

  /// Height of a primary (full-width) action button.
  static const primaryButtonHeight = 50.0;

  /// Height of the floating glass tab bar capsule.
  static const tabBarHeight = 62.0;

  /// Gap between the floating action button and whatever is below it.
  static const floatingActionGap = 12.0;

  /// Backdrop blur sigma used by glass surfaces.
  static const glassBlur = 20.0;
}

/// The spec type scale (SF on iOS). Colours come from the theme.
class AppTypography {
  AppTypography._();

  /// Large title 34/41 bold (screen titles).
  static const largeTitle = TextStyle(
      fontSize: 34,
      height: 41 / 34,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4);

  /// Title 2 22/28 bold (card titles such as a school name).
  static const title2 = TextStyle(
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.26);

  /// Title 3 20/25 semibold (sheet titles).
  static const title3 = TextStyle(
      fontSize: 20,
      height: 25 / 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.45);

  /// Headline 17/22 semibold.
  static const headline = TextStyle(
      fontSize: 17,
      height: 22 / 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.43);

  /// Body 17/22.
  static const body =
      TextStyle(fontSize: 17, height: 22 / 17, letterSpacing: -0.43);

  /// Subheadline 15/20 (secondary lines, subtitles).
  static const subheadline =
      TextStyle(fontSize: 15, height: 20 / 15, letterSpacing: -0.23);

  /// Footnote 13/18 (section labels when semibold, captions).
  static const footnote =
      TextStyle(fontSize: 13, height: 18 / 13, letterSpacing: -0.08);

  /// Tab bar label 10/12 semibold.
  static const tabLabel =
      TextStyle(fontSize: 10, height: 1.2, fontWeight: FontWeight.w600);
}

/// Neutral colour tokens for light/dark × normal/high-contrast.
///
/// Colour is reserved for year levels (see `YearLevelColors`); everything here
/// is neutral except [warningTint]/[warningInk] (amber, tint only), the
/// completion status pair [success] (done green) / [progress] (partial amber
/// ring) and the error tokens.
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

  /// Screen background.
  Color get canvas => dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

  /// Cards and other opaque content.
  Color get surface => dark ? const Color(0xFF1C1C1E) : Colors.white;

  /// Opaque grey (the [fill] composited on [surface]): tiles, pills, tracks,
  /// secondary buttons, input fills. Use this where a solid colour is needed.
  Color get surfaceQuiet => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFF2C2C2E),
        (true, false) => const Color(0xFF323235),
        (false, true) => const Color(0xFFE5E5EA),
        (false, false) => const Color(0xFFEFEFF0),
      };

  /// Translucent grey fill from the spec (adapts to what is beneath it).
  Color get fill => highContrast
      ? surfaceQuiet
      : dark
          ? const Color(0x3D767680)
          : const Color(0x1F767680);

  /// Track of a segmented control.
  Color get segmentTrack => fill;

  /// Selected segment: white on the grey track in light themes, a lighter
  /// grey than the track in dark themes (as on iOS), so selection never reads
  /// inverted.
  Color get segmentThumb => dark ? const Color(0xFF636366) : surface;

  /// Opaque hairline / border colour. Visible (≥3:1) in high contrast.
  Color get outline => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFF8E8E93),
        (true, false) => const Color(0xFF38383A),
        (false, true) => const Color(0xFF6E6E73),
        (false, false) => const Color(0xFFD1D1D6),
      };

  /// List separators (translucent in normal contrast).
  Color get separator => highContrast
      ? outline
      : dark
          ? const Color(0x24FFFFFF)
          : const Color(0x1F000000);

  /// Primary text and glyphs.
  Color get ink => switch ((dark, highContrast)) {
        (true, true) => Colors.white,
        (true, false) => const Color(0xFFF5F5F7),
        (false, true) => Colors.black,
        (false, false) => const Color(0xFF1A1A1A),
      };

  /// Secondary text.
  Color get muted => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFFD1D1D6),
        (true, false) => const Color(0xFFA1A1A6),
        (false, true) => const Color(0xFF3A3D42),
        (false, false) => const Color(0xFF5B6068),
      };

  /// Disclosure chevrons.
  Color get chevron => highContrast
      ? muted
      : dark
          ? const Color(0xFF8E8E93)
          : const Color(0xFF8A8F98);

  /// Empty "not started" ring, grabbers and other inactive marks.
  Color get inactive => highContrast ? muted : const Color(0xFF8E8E93);

  /// Track behind a partial progress ring.
  Color get ringTrack => highContrast
      ? outline
      : dark
          ? const Color(0xFF3A3A3C)
          : const Color(0xFFD1D1D6);

  /// "Done" green: the solid disc of a completed task (classroom packs
  /// complete, consumable delivered, checklist complete, visit signed off).
  /// Status only — never buttons, links or tiles. ≥ 3:1 against [surface] and
  /// [canvas] (≥ 4.5:1 in high contrast); deliberately not the Year 3 fill.
  Color get success => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFF3DDC68),
        (true, false) => const Color(0xFF30D158),
        (false, true) => const Color(0xFF0D7F3F),
        (false, false) => const Color(0xFF1A9850),
      };

  /// Tick drawn on [success] (≥ 3:1 against it).
  Color get onSuccess => switch ((dark, highContrast)) {
        (true, true) => Colors.black,
        (true, false) => const Color(0xFF0B1611),
        (false, _) => Colors.white,
      };

  /// Solid amber arc of a partial ("in progress") ring. ≥ 3:1 against
  /// [surface] and [canvas] (≥ 4.5:1 in high contrast). Warnings keep the
  /// pale [warningTint] / [warningInk] pair.
  Color get progress => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFFFFC65E),
        (true, false) => const Color(0xFFFFB340),
        (false, true) => const Color(0xFF975C00),
        (false, false) => const Color(0xFFC27000),
      };

  /// Primary action fill (ink; inverted in dark mode).
  Color get action => ink;

  /// Label on [action].
  Color get onAction => switch ((dark, highContrast)) {
        (true, true) => Colors.black,
        (true, false) => const Color(0xFF1A1A1A),
        (false, _) => Colors.white,
      };

  /// Pale amber background of warnings (never a solid fill).
  Color get warningTint => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFF2E240C),
        (true, false) => const Color(0xFF3A2E12),
        (false, true) => const Color(0xFFFFF4D6),
        (false, false) => const Color(0xFFFFF4D6),
      };

  /// Dark amber text / icon on [warningTint].
  Color get warningInk => switch ((dark, highContrast)) {
        (true, true) => const Color(0xFFFFE3A8),
        (true, false) => const Color(0xFFFFD98A),
        (false, true) => const Color(0xFF5C3800),
        (false, false) => const Color(0xFF7A4A00),
      };

  /// Clear glass fill (tab bar, nav buttons, sheets).
  Color get glassFill =>
      dark ? const Color(0x8C28282A) : const Color(0x9EFFFFFF);

  /// Glass sheets: [surface] at ~90 % over the blur, so only a hint of what is
  /// behind shows through and text never sits on a visible smudge.
  Color get sheetGlassFill => surface.withValues(alpha: 0.92);

  /// Peak opacity colour of the soft shadow drawn outside glass controls.
  Color get glassShadow =>
      dark ? const Color(0x33000000) : const Color(0x14000000);

  /// 0.5 pt hairline around glass.
  Color get glassEdge =>
      dark ? const Color(0x2EFFFFFF) : const Color(0x14000000);

  /// Tinted glass (the floating primary action): [action] at ~85 %.
  Color get tintedGlassFill =>
      dark ? const Color(0xD9F5F5F7) : const Color(0xD91A1A1A);

  /// Soft neutral shadow under raised elements (selected segment, dragged
  /// row).
  Color get shadow => const Color(0x1F000000);

  /// Modal barrier behind sheets.
  Color get scrim => const Color(0x38000000);

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

/// Tint/ink pairs for tiles, pills and panels.
///
/// The UI is neutral: only [neutral] and [warning] exist.
enum AppTone {
  /// Grey tint with ink text.
  neutral,

  /// Pale amber tint with dark amber ink: something must be decided.
  warning;

  Color inkFor(BuildContext context) => inkOn(AppPalette.of(context));
  Color tintFor(BuildContext context) => tintOn(AppPalette.of(context));

  /// Background tint for this tone.
  Color tintOn(AppPalette colors) =>
      this == warning ? colors.warningTint : colors.surfaceQuiet;

  /// Text / glyph colour on [tintOn].
  Color inkOn(AppPalette colors) =>
      this == warning ? colors.warningInk : colors.ink;
}
