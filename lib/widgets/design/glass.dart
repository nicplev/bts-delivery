import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import 'app_icons.dart';

/// Whether glass should render as an opaque surface (high contrast).
bool appGlassIsOpaque(BuildContext context) =>
    AppPalette.of(context).highContrast ||
    (MediaQuery.maybeHighContrastOf(context) ?? false);

/// A Liquid Glass surface: blur + translucent fill + hairline + soft shadow.
///
/// Use only on the functional layer (tab bar, nav buttons, the floating
/// primary action, sheets, nav-area status). In high contrast it becomes an
/// opaque [AppPalette.surface] (or [AppPalette.action] when [tinted]) with a
/// visible outline and no blur.
class AppGlass extends StatelessWidget {
  const AppGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.tinted = false,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
  });

  final Widget child;

  /// Shape of the glass; the default is a capsule.
  final BorderRadius borderRadius;

  /// Ink-tinted glass for the one primary action of a screen.
  final bool tinted;

  final EdgeInsetsGeometry padding;

  /// Draw the soft drop shadow (off for glass sitting inside other glass).
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final content = Padding(padding: padding, child: child);
    if (appGlassIsOpaque(context)) {
      return DecoratedBox(
        key: const ValueKey('app-glass-opaque'),
        decoration: BoxDecoration(
          color: tinted ? colors.action : colors.surface,
          borderRadius: borderRadius,
          border: Border.all(color: colors.outline, width: 1.5),
        ),
        child: content,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow ? AppTokens.glassShadow : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: AppTokens.glassBlur, sigmaY: AppTokens.glassBlur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tinted ? colors.tintedGlassFill : colors.glassFill,
              borderRadius: borderRadius,
              border: Border.all(color: colors.glassEdge, width: 0.5),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Tap target with an iOS-style dim-on-press highlight (no ripple), button
/// semantics and keyboard focus.
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.selected,
    this.excludeChildSemantics = false,
    this.pressedColor,
  });

  final Widget child;

  /// When set, a pressed control paints this background instead of dimming
  /// (used by list rows).
  final Color? pressedColor;

  /// `null` disables the control.
  final VoidCallback? onTap;

  /// Overrides the label read by screen readers.
  final String? semanticLabel;

  /// Sets the selected semantics flag when non-null.
  final bool? selected;

  /// Hide the child's own semantics (use with [semanticLabel]).
  final bool excludeChildSemantics;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  Widget _visual(bool enabled, bool reduceMotion) {
    final child = widget.excludeChildSemantics
        ? ExcludeSemantics(child: widget.child)
        : widget.child;
    final pressedColor = widget.pressedColor;
    if (pressedColor != null) {
      return Opacity(
        opacity: enabled ? 1 : 0.45,
        child: ColoredBox(
          color: _pressed ? pressedColor : Colors.transparent,
          child: child,
        ),
      );
    }
    return AnimatedOpacity(
      opacity: !enabled
          ? 0.45
          : _pressed
              ? 0.6
              : 1,
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
      child: child,
    );
  }

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => widget.onTap?.call()),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onTap,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: enabled ? () => _set(false) : null,
          child: _visual(enabled, reduceMotion),
        ),
      ),
    );
  }
}

/// 44 pt round glass button for the nav area (back, options…).
class AppGlassIconButton extends StatelessWidget {
  const AppGlassIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.size = AppTokens.navButtonSize,
    this.iconSize = 20,
  });

  final IconData icon;

  /// Read by screen readers, e.g. "Back" or "Visit options".
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      excludeChildSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: AppGlass(
          borderRadius: BorderRadius.circular(size / 2),
          child: Center(child: Icon(icon, size: iconSize, color: colors.ink)),
        ),
      ),
    );
  }
}

/// Glass status capsule for the nav area (icon + label, e.g. "Offline").
class AppGlassStatus extends StatelessWidget {
  const AppGlassStatus({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.navButtonSize),
        child: AppGlass(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: colors.ink),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.subheadline
                      .copyWith(fontWeight: FontWeight.w600, color: colors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width 50 pt tinted-glass button: the one floating primary action of a
/// screen. Shows a spinner when [loading]; disabled when [onPressed] is null
/// or [loading].
class AppGlassPrimaryButton extends StatelessWidget {
  const AppGlassPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final enabled = onPressed != null && !loading;
    final ink = enabled ? colors.onAction : colors.muted;
    return AppPressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: label,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            minHeight: AppTokens.primaryButtonHeight,
            minWidth: double.infinity),
        child: AppGlass(
          tinted: enabled,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox.square(
                    dimension: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.2, color: ink),
                  ),
                )
              else if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(icon, size: 20, color: ink),
                ),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.headline.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floats one primary [action] above the tab bar / home indicator over
/// scrolling [child] content, and adds the space it covers to the child's
/// `MediaQuery` bottom padding (read it with `AppInsets.scroll(context)` or let
/// a `ListView` without explicit padding pick it up).
class AppFloatingActionArea extends StatelessWidget {
  const AppFloatingActionArea({super.key, required this.child, this.action});

  final Widget child;

  /// Usually an [AppGlassPrimaryButton]; `null` shows nothing.
  final Widget? action;

  /// Bottom space the floating action covers (button + gap), text-scale aware.
  static double reservedHeight(BuildContext context) {
    final buttonHeight = math.max(AppTokens.primaryButtonHeight,
        MediaQuery.textScalerOf(context).scale(22) + 24);
    return buttonHeight + AppTokens.floatingActionGap * 2;
  }

  @override
  Widget build(BuildContext context) {
    if (action == null) return child;
    final media = MediaQuery.of(context);
    final reserve = reservedHeight(context);
    final bottom = media.padding.bottom + reserve;
    return Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(bottom: bottom),
              viewPadding: media.viewPadding
                  .copyWith(bottom: math.max(media.viewPadding.bottom, bottom)),
            ),
            child: child,
          ),
        ),
        Positioned(
          left: AppTokens.gutter,
          right: AppTokens.gutter,
          bottom: media.padding.bottom + AppTokens.floatingActionGap,
          child: action!,
        ),
      ],
    );
  }
}

/// Shows a glass modal sheet inset 8 pt from the screen edges (radius 36) with
/// a grabber, [title] and a close button above [builder]'s content.
///
/// Built on [showModalBottomSheet] (dismissible by drag, barrier tap and the
/// back gesture). Uses the root navigator by default so it covers the tab bar.
/// Scrollable content should size itself (e.g. `shrinkWrap: true`); the sheet
/// is limited to 90 % of the screen height.
Future<T?> showAppGlassSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
  String closeLabel = 'Close',
  EdgeInsetsGeometry contentPadding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: AppPalette.of(context).scrim,
    builder: (sheetContext) => AppGlassSheetFrame(
      title: title,
      closeLabel: closeLabel,
      contentPadding: contentPadding,
      child: Builder(builder: builder),
    ),
  );
}

/// The frame drawn by [showAppGlassSheet]; usable on its own inside a custom
/// modal route.
class AppGlassSheetFrame extends StatelessWidget {
  const AppGlassSheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.closeLabel = 'Close',
    this.contentPadding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
  });

  final String title;
  final Widget child;
  final String closeLabel;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final media = MediaQuery.of(context);
    const inset = AppTokens.sheetInset;
    final bottomSafe = math.max(0.0, media.viewPadding.bottom - inset * 2);
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, media.viewPadding.top + inset, inset,
          inset + media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: AppGlass(
          borderRadius: BorderRadius.circular(AppTokens.sheetRadius),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.inactive,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(title,
                              style: AppTypography.title3
                                  .copyWith(color: colors.ink)),
                        ),
                      ),
                      AppPressable(
                        onTap: () => Navigator.of(context).maybePop(),
                        semanticLabel: closeLabel,
                        excludeChildSemantics: true,
                        child: SizedBox.square(
                          dimension: AppTokens.minTouchTarget,
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: colors.fill, shape: BoxShape.circle),
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Icon(AppIcons.close,
                                    size: 18, color: colors.ink),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding:
                        contentPadding.add(EdgeInsets.only(bottom: bottomSafe)),
                    child: Material(
                      type: MaterialType.transparency,
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
