import 'package:flutter/material.dart';

import '../app/theme/app_tokens.dart';

/// The seven school year levels that carry a colour (company convention).
///
/// Anything else (specialist, composite, "Year 7", unknown) is not a
/// [SchoolYear] and is shown with the neutral style.
enum SchoolYear {
  prep('P', 'Prep'),
  year1('1', 'Year 1'),
  year2('2', 'Year 2'),
  year3('3', 'Year 3'),
  year4('4', 'Year 4'),
  year5('5', 'Year 5'),
  year6('6', 'Year 6');

  const SchoolYear(this.shortLabel, this.label);

  /// Badge text: "P", "1" … "6".
  final String shortLabel;

  /// Words for semantics and visible copy: "Prep", "Year 1" …
  final String label;

  static final _prep = RegExp(r'\b(?:prep|foundation)\b');
  static final _numbered =
      RegExp(r'\b(?:year|yr|grade|gr|y)\s*\.?\s*(\d{1,2})(?!\d)');
  static final _composite = RegExp(
      r'\b(?:composite|specialist|split|multi[- ]?age)\b|\d\s*[/&+]\s*\d');

  /// Parses a free-text year-level label ("Prep", "Foundation", "Year 1",
  /// "Yr 3", "Grade 2", "Year 2 – Room B"…). Returns `null` for anything that
  /// is not exactly one of the seven year levels.
  static SchoolYear? parse(String? label) {
    if (label == null) return null;
    final name = label.toLowerCase();
    if (_composite.hasMatch(name)) return null;
    final isPrep = _prep.hasMatch(name);
    final numbers = {
      for (final match in _numbered.allMatches(name))
        int.parse(match.group(1)!),
    };
    if (isPrep) return numbers.isEmpty ? prep : null;
    if (numbers.length != 1) return null;
    final year = numbers.single;
    return year >= 1 && year <= 6 ? values[year] : null;
  }
}

/// How a year level (or the neutral fallback) is drawn.
@immutable
class YearLevelStyle {
  const YearLevelStyle({
    required this.fill,
    required this.onFill,
    required this.shortLabel,
    required this.needsBorder,
    this.year,
  });

  /// The parsed year, or `null` for the neutral style.
  final SchoolYear? year;

  /// Badge / header background.
  final Color fill;

  /// Text and glyphs on [fill].
  final Color onFill;

  /// Badge text ("P", "1" … "6", or an initial for neutral labels).
  final String shortLabel;

  /// Whether a 1 px light hairline is needed to keep [fill] visible
  /// (Prep in dark mode).
  final bool needsBorder;

  bool get isYear => year != null;
}

/// The single source of truth for year-level colours.
///
/// The hex values are provisional (the owner may send exact company values);
/// change them here only.
class YearLevelColors {
  YearLevelColors._();

  static const _darkLabel = Color(0xFF0B1611);

  /// Year fill colours.
  static const Map<SchoolYear, Color> fills = {
    SchoolYear.prep: Color(0xFF1A1A1A),
    SchoolYear.year1: Color(0xFFD62828),
    SchoolYear.year2: Color(0xFF00AEEF),
    SchoolYear.year3: Color(0xFF2BB673),
    SchoolYear.year4: Color(0xFF7B3FC4),
    SchoolYear.year5: Color(0xFFF9ED32),
    SchoolYear.year6: Color(0xFFF58220),
  };

  /// Label colours on [fills].
  static const Map<SchoolYear, Color> labels = {
    SchoolYear.prep: Colors.white,
    SchoolYear.year1: Colors.white,
    SchoolYear.year2: _darkLabel,
    SchoolYear.year3: _darkLabel,
    SchoolYear.year4: Colors.white,
    SchoolYear.year5: _darkLabel,
    SchoolYear.year6: _darkLabel,
  };

  /// Hairline drawn around Prep in dark mode.
  static Color borderColor(AppPalette colors) =>
      colors.dark ? const Color(0x66FFFFFF) : colors.outline;

  /// Style for a known year (or neutral when [year] is null).
  static YearLevelStyle styleFor(
    SchoolYear? year,
    AppPalette colors, {
    String? neutralShortLabel,
  }) {
    if (year == null) {
      return YearLevelStyle(
        fill: colors.surfaceQuiet,
        onFill: colors.ink,
        shortLabel: neutralShortLabel ?? '',
        needsBorder: colors.highContrast,
      );
    }
    return YearLevelStyle(
      year: year,
      fill: fills[year]!,
      onFill: labels[year]!,
      shortLabel: year.shortLabel,
      needsBorder: year == SchoolYear.prep && colors.dark,
    );
  }

  /// Style for a free-text label (e.g. a `YearLevel.label`).
  static YearLevelStyle styleOf(BuildContext context, String label) =>
      styleForLabel(label, AppPalette.of(context));

  /// Style for a free-text label with an explicit palette.
  static YearLevelStyle styleForLabel(String label, AppPalette colors) =>
      styleFor(SchoolYear.parse(label), colors,
          neutralShortLabel: _initial(label));

  static String _initial(String label) {
    final match = RegExp(r'[A-Za-z0-9]').firstMatch(label);
    return match == null ? '' : match.group(0)!.toUpperCase();
  }

  /// Legacy: background colour for a label (year fill or neutral grey).
  static Color getBackgroundColor(BuildContext context, String label) =>
      styleOf(context, label).fill;

  /// Legacy: glyph colour on [getBackgroundColor].
  static Color getIconColor(BuildContext context, String label) =>
      styleOf(context, label).onFill;

  /// Legacy: whether the badge for [label] needs a hairline border. Without a
  /// [context] this is true for Prep in any mode; pass one for the exact
  /// answer (Prep in dark mode only).
  static bool needsBorder(String label, [BuildContext? context]) {
    if (context != null) return styleOf(context, label).needsBorder;
    return SchoolYear.parse(label) == SchoolYear.prep;
  }
}
