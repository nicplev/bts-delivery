import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import 'app_icons.dart';
import 'cards.dart';

/// A school's optional logo, cropped to the same rounded square as an
/// [AppIconTile] (sizes ≈ 29, 40, 48), with a hairline so white logos stay
/// visible on white cards.
///
/// With no [logo], while it loads, offline without a cached copy or on any
/// error it shows the default school icon tile instead — never a broken image
/// or a spinner, and the size never changes.
///
/// The logo is decorative unless [semanticLabel] is given (use one only where
/// the image adds information, e.g. a standalone logo preview).
class AppSchoolAvatar extends StatelessWidget {
  const AppSchoolAvatar({
    super.key,
    this.logo,
    this.size = 40,
    this.semanticLabel,
  });

  final ImageProvider? logo;
  final double size;
  final String? semanticLabel;

  /// The corner radius [AppIconTile] uses at [size].
  static double radiusFor(double size) => size <= 32
      ? 7.0
      : size >= 46
          ? 14.0
          : AppTokens.controlRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = AppIconTile(icon: AppIcons.school, size: size);
    final image = logo;
    if (image == null) return fallback;

    final colors = AppPalette.of(context);
    final radius = BorderRadius.circular(radiusFor(size));
    final avatar = SizedBox.square(
      dimension: size,
      child: Image(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
        frameBuilder: (context, child, frame, synchronous) {
          if (frame == null && !synchronous) return fallback;
          return DecoratedBox(
            key: const ValueKey('school-logo-image'),
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: colors.highContrast ? colors.outline : colors.separator,
                width: colors.highContrast ? 1 : 0.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: ColoredBox(color: colors.surface, child: child),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: avatar);
    return Semantics(image: true, label: label, child: avatar);
  }
}
