import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import 'app_icons.dart';

/// Completion state shown by [AppStatusRing].
enum AppCompletion {
  complete('Complete'),
  partial('Partial'),
  notStarted('Not started');

  const AppCompletion(this.label);

  /// Default words for semantics and pills.
  final String label;

  /// Derives the state from counts (`done >= total > 0` is complete).
  static AppCompletion fromCounts(int done, int total) {
    if (total > 0 && done >= total) return complete;
    if (done > 0) return partial;
    return notStarted;
  }
}

/// Status without colour: complete = solid ink check-circle, partial = ink
/// arc for [progress] (0–1) on a grey track, not started = empty grey ring.
/// Always carries a semantics label (defaults to the state's words).
class AppStatusRing extends StatelessWidget {
  const AppStatusRing({
    super.key,
    required this.status,
    this.progress = 0,
    this.size = 22,
    this.semanticLabel,
  });

  /// Builds the ring from counts ("13 of 24" → partial at 0.54).
  factory AppStatusRing.fromCounts({
    Key? key,
    required int done,
    required int total,
    double size = 22,
    String? semanticLabel,
  }) =>
      AppStatusRing(
        key: key,
        status: AppCompletion.fromCounts(done, total),
        progress: total <= 0 ? 0 : (done / total).clamp(0.0, 1.0),
        size: size,
        semanticLabel: semanticLabel,
      );

  final AppCompletion status;

  /// Fraction drawn for [AppCompletion.partial].
  final double progress;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final Widget glyph = switch (status) {
      AppCompletion.complete =>
        Icon(AppIcons.complete, size: size, color: colors.ink),
      AppCompletion.partial => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(
            track: colors.ringTrack,
            arc: colors.ink,
            progress: progress.clamp(0.0, 1.0),
            stroke: size * 3 / 22,
          ),
        ),
      AppCompletion.notStarted => CustomPaint(
          size: Size.square(size),
          painter: _RingPainter(
            track: colors.inactive,
            arc: colors.inactive,
            progress: 0,
            stroke: size * 2 / 22,
          ),
        ),
    };
    return Semantics(
      label: semanticLabel ?? status.label,
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: Center(child: glyph)),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.track,
    required this.arc,
    required this.progress,
    required this.stroke,
  });

  final Color track;
  final Color arc;
  final double progress;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Matches the mockup: r = 8.5 in a 22 box.
    final radius = size.shortestSide * 8.5 / 22;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, paint);
    if (progress <= 0) return;
    paint
      ..color = arc
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.track != track ||
      old.arc != arc ||
      old.progress != progress ||
      old.stroke != stroke;
}

/// Small capsule label ("Partial", "Not started"): neutral grey with ink text,
/// or amber with [AppTone.warning].
class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    super.key,
    required this.label,
    this.icon,
    this.tone = AppTone.neutral,
  });

  final String label;
  final IconData? icon;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final ink = tone.inkFor(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.tintFor(context),
        borderRadius: BorderRadius.circular(AppTokens.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: ink, size: 14),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: AppTypography.footnote
                    .copyWith(color: ink, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4 pt ink progress bar on a grey track, with a semantics label and value.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.semanticLabel,
    this.semanticValue,
    this.height = 4,
  });

  /// 0–1.
  final double value;

  /// E.g. "Packs recorded".
  final String? semanticLabel;

  /// Defaults to a percentage ("54%").
  final String? semanticValue;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return LinearProgressIndicator(
      value: clamped,
      minHeight: height,
      color: colors.ink,
      backgroundColor: colors.surfaceQuiet,
      borderRadius: BorderRadius.circular(height),
      semanticsLabel: semanticLabel,
      semanticsValue: semanticValue ?? '${(clamped * 100).round()}%',
    );
  }
}

/// Inline notice: icon + text in a radius-12 box, min height 44. Neutral grey
/// by default; [AppNotice.warning] is the single amber warning style (use it
/// only where someone must decide something before sign-off).
class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    this.icon = AppIcons.info,
    this.trailing,
  }) : warning = false;

  /// Pale amber notice with dark amber text and a warning triangle.
  const AppNotice.warning({
    super.key,
    required this.message,
    this.icon = AppIcons.warning,
    this.trailing,
  }) : warning = true;

  final String message;
  final IconData icon;

  /// Optional action on the right (e.g. a small [TextButton]).
  final Widget? trailing;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final ink = warning ? colors.warningInk : colors.ink;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTokens.minTouchTarget),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: warning ? colors.warningTint : colors.surfaceQuiet,
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: warning ? ink : colors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: AppTypography.subheadline.copyWith(
                    color: ink,
                    fontWeight: warning ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Amber warning notice (alias of [AppNotice.warning]).
class AppWarningNotice extends AppNotice {
  const AppWarningNotice({super.key, required super.message, super.trailing})
      : super.warning();
}

/// Small inline status: ink icon + 13 pt muted text
/// (e.g. "Saved to server · 10:42 AM").
class AppStatusLine extends StatelessWidget {
  const AppStatusLine({
    super.key,
    required this.text,
    this.icon = AppIcons.savedToServer,
    this.iconColor,
  });

  final String text;
  final IconData icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor ?? colors.ink),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.footnote.copyWith(color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
