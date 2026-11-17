import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../utils/year_level_colors.dart';
import 'glass.dart';

/// Round badge with a year's short label ("P", "1"…"6") in the year colours;
/// neutral grey with an initial for anything that is not a year level.
///
/// Decorative by default (the year is written in words nearby); pass
/// [semanticLabel] to make it speak.
class AppYearBadge extends StatelessWidget {
  const AppYearBadge({
    super.key,
    required this.label,
    this.size = 36,
    this.semanticLabel,
  });

  /// Badge for a parsed [SchoolYear] (null → neutral, no text).
  AppYearBadge.year(SchoolYear? year,
      {super.key, this.size = 36, this.semanticLabel})
      : label = year?.label ?? '';

  /// Free-text year label ("Year 1", "Prep", "Specialist"…).
  final String label;

  /// 36 in lists, 44 in the filter row.
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final style = YearLevelColors.styleForLabel(label, colors);
    final badge = _YearCircle(style: style, size: size, colors: colors);
    if (semanticLabel == null) return ExcludeSemantics(child: badge);
    return Semantics(
        label: semanticLabel, excludeSemantics: true, child: badge);
  }
}

class _YearCircle extends StatelessWidget {
  const _YearCircle(
      {required this.style, required this.size, required this.colors});

  final YearLevelStyle style;
  final double size;
  final AppPalette colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style.fill,
          shape: BoxShape.circle,
          border: style.needsBorder
              ? Border.all(color: YearLevelColors.borderColor(colors))
              : null,
        ),
        child: Center(
          child: MediaQuery.withNoTextScaling(
            child: Text(
              style.shortLabel,
              style: TextStyle(
                fontSize: size * (size >= 40 ? 17 / 44 : 15 / 36),
                fontWeight: FontWeight.w700,
                height: 1,
                color: style.onFill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of seven 44 pt year circles for filtering; scrolls horizontally when
/// it does not fit. Selected years show an ink ring. Each circle is a button
/// labelled "Prep", "Year 1"… with the selected state.
class AppYearFilter extends StatelessWidget {
  const AppYearFilter({
    super.key,
    required this.selected,
    required this.onToggle,
    this.years = SchoolYear.values,
    this.semanticLabel = 'Filter by year level',
    this.padding = EdgeInsets.zero,
  });

  /// Currently selected years (empty = no filter).
  final Set<SchoolYear> selected;

  /// Called with the tapped year; the caller updates [selected].
  final ValueChanged<SchoolYear> onToggle;

  /// Which years to show (e.g. only those present at the school).
  final List<SchoolYear> years;
  final String semanticLabel;

  /// Scroll padding (use the screen gutter when the row bleeds to the edges).
  final EdgeInsetsGeometry padding;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      explicitChildNodes: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < years.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _chip(colors, years[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(AppPalette colors, SchoolYear year) {
    final isSelected = selected.contains(year);
    final style = YearLevelColors.styleFor(year, colors);
    return AppPressable(
      key: ValueKey('year-filter-${year.name}'),
      onTap: () => onToggle(year),
      semanticLabel: year.label,
      selected: isSelected,
      excludeChildSemantics: true,
      child: SizedBox.square(
        dimension: _size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                isSelected ? Border.all(color: colors.ink, width: 2.5) : null,
          ),
          child: Padding(
            padding: EdgeInsets.all(isSelected ? 4.5 : 0),
            child: _YearCircle(
              style: style,
              size: isSelected ? _size - 9 : _size,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }
}
