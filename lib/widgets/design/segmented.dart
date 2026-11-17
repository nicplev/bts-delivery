import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import 'glass.dart';

/// One option of an [AppSegmentedControl].
@immutable
class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.key});

  final T value;
  final String label;

  /// Key for the segment's tap target (tests, e.g. `ValueKey('hub-tab-0')`).
  final Key? key;
}

/// iOS-style segmented control: a grey track with the selected option on a
/// raised thumb (white in light themes, a lighter grey than the track in dark
/// themes). Each segment is a button with the selected state.
///
/// All labels scale identically: when the widest label does not fit its
/// segment, every label shrinks by the same factor (words never break). With
/// [allowVertical], options that would have to shrink noticeably stack
/// vertically instead (large text sizes).
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
    this.allowVertical = false,
  });

  final List<AppSegment<T>> segments;

  /// The selected value (`null` = nothing selected).
  final T? selected;
  final ValueChanged<T> onChanged;

  /// Label of the group for screen readers.
  final String? semanticLabel;

  /// Stack the options vertically when they do not fit side by side.
  final bool allowVertical;

  static const double _trackPadding = 2;
  static const double _labelPadding = 6;
  static const TextStyle _style = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    letterSpacing: -0.23,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final measureStyle = DefaultTextStyle.of(context).style.merge(_style);
    return Semantics(
      container: true,
      label: semanticLabel,
      explicitChildNodes: true,
      child: LayoutBuilder(builder: (context, constraints) {
        final count = segments.length;
        var factor = 1.0;
        if (constraints.maxWidth.isFinite && count > 0) {
          final slot = (constraints.maxWidth - _trackPadding * 2) / count -
              _labelPadding * 2;
          var widest = 0.0;
          for (final segment in segments) {
            final painter = TextPainter(
              text: TextSpan(text: segment.label, style: measureStyle),
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            widest = math.max(widest, painter.width);
            painter.dispose();
          }
          if (widest > slot && widest > 0) factor = slot / widest * 0.98;
        }
        final vertical = allowVertical && factor < 0.85;
        final labelScaler = vertical
            ? scaler
            : TextScaler.linear(scaler.scale(15) / 15 * factor);
        final items = [
          for (final segment in segments)
            AppPressable(
              key: segment.key,
              onTap: () => onChanged(segment.value),
              semanticLabel: segment.label,
              selected: segment.value == selected,
              excludeChildSemantics: true,
              child: _thumb(
                colors,
                segment.label,
                labelScaler,
                selected: segment.value == selected,
              ),
            ),
        ];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.segmentTrack,
            borderRadius: BorderRadius.circular(
                vertical ? AppTokens.controlRadius + 8 : AppTokens.pillRadius),
            border: colors.highContrast
                ? Border.all(color: colors.outline, width: 1.5)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(_trackPadding),
            child: vertical
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(height: 2),
                        items[i],
                      ],
                    ],
                  )
                : Row(
                    children: [
                      for (final item in items) Expanded(child: item),
                    ],
                  ),
          ),
        );
      }),
    );
  }

  Widget _thumb(
    AppPalette colors,
    String label,
    TextScaler labelScaler, {
    required bool selected,
  }) {
    const radius = BorderRadius.all(Radius.circular(AppTokens.pillRadius));
    return CustomPaint(
      // A soft lift under the white thumb (light themes only).
      foregroundPainter: selected && !colors.highContrast && !colors.dark
          ? AppGlassShadowPainter(
              borderRadius: radius, color: colors.glassShadow)
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? colors.segmentThumb : null,
            borderRadius: radius,
            border: selected && colors.highContrast
                ? Border.all(color: colors.ink, width: 1.5)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: _labelPadding, vertical: 8),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                textScaler: labelScaler,
                style: _style.copyWith(
                    color: selected ? colors.ink : colors.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
