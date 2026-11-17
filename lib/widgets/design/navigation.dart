import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_tokens.dart';
import '../../utils/year_level_colors.dart';
import 'app_icons.dart';
import 'glass.dart';

/// Padding helpers so scrolling content clears the floating chrome.
abstract final class AppInsets {
  /// Scroll padding: [horizontal] gutters, `MediaQuery` top padding (status bar
  /// and a transparent [AppNavBar]) + [top], and `MediaQuery` bottom padding
  /// (tab bar, home indicator, floating action) + [bottom].
  static EdgeInsets scroll(
    BuildContext context, {
    double top = 8,
    double bottom = 24,
    double horizontal = AppTokens.gutter,
  }) {
    final padding = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
        horizontal, padding.top + top, horizontal, padding.bottom + bottom);
  }

  /// Only the bottom space covered by the tab bar / floating action + [extra].
  static double bottom(BuildContext context, {double extra = 24}) =>
      MediaQuery.paddingOf(context).bottom + extra;
}

/// Pops the current route through go_router when it can, else the navigator.
void appNavigateBack(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
  } else {
    Navigator.maybePop(context);
  }
}

bool _canGoBack(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null) return router.canPop();
  return Navigator.canPop(context);
}

/// Transparent top bar with floating glass buttons: back on the leading side,
/// [actions] (glass buttons / [AppGlassStatus]) on the trailing side, no title.
///
/// Pair with `Scaffold(extendBodyBehindAppBar: true)` and put an
/// [AppLargeTitle] (or [AppYearHeader]) at the top of the scrolling content so
/// the title scrolls with it. Back uses go_router (`context.pop()`), falling
/// back to `Navigator.maybePop`.
class AppNavBar extends StatelessWidget implements PreferredSizeWidget {
  const AppNavBar({
    super.key,
    this.actions = const [],
    this.showBack,
    this.onBack,
    this.backLabel = 'Back',
    this.title,
  });

  /// Trailing widgets, spaced 8 pt (e.g. [AppGlassIconButton]).
  final List<Widget> actions;

  /// Force the back button on/off; by default shown when a route can be popped.
  final bool? showBack;

  /// Overrides the back behaviour.
  final VoidCallback? onBack;

  /// Semantics label of the back button ("Back" or "Back to Oakfield Primary").
  final String backLabel;

  /// Optional small centred title (most screens use [AppLargeTitle] instead).
  final String? title;

  static const double height = AppTokens.navButtonSize + 8;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final back = showBack ?? _canGoBack(context);
    final colors = AppPalette.of(context);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.gutter, vertical: 4),
          child: NavigationToolbar(
            leading: back
                ? AppGlassIconButton(
                    icon: AppIcons.back,
                    semanticLabel: backLabel,
                    onPressed: onBack ?? () => appNavigateBack(context),
                  )
                : null,
            middle: title == null
                ? null
                : Semantics(
                    header: true,
                    child: Text(title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTypography.headline.copyWith(color: colors.ink)),
                  ),
            trailing: actions.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Large title (34 pt bold) with an optional subtitle, scrolling with content.
class AppLargeTitle extends StatelessWidget {
  const AppLargeTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final String title;

  /// Muted 15 pt line under the title.
  final String? subtitle;

  /// Custom subtitle (e.g. an [AppStatusLine]); replaces [subtitle].
  final Widget? subtitleWidget;

  /// Default assumes it sits inside the 16 pt screen gutter.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final sub = subtitleWidget ??
        (subtitle == null
            ? null
            : Text(subtitle!,
                style:
                    AppTypography.subheadline.copyWith(color: colors.muted)));
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(title,
                style: AppTypography.largeTitle.copyWith(color: colors.ink)),
          ),
          if (sub != null) ...[const SizedBox(height: 4), sub],
        ],
      ),
    );
  }
}

/// Full-bleed year-coloured classroom header (bottom corners 28) with the
/// title and subtitle in the year's label colour.
///
/// Place it first in a scroll view with zero top padding, under a transparent
/// [AppNavBar] (`Scaffold(extendBodyBehindAppBar: true)`): it pads itself by
/// the `MediaQuery` top padding so the glass buttons float on the colour.
/// The subtitle should name the year in words ("Year 1 · Oakfield Primary").
class AppYearHeader extends StatelessWidget {
  const AppYearHeader({
    super.key,
    required this.title,
    required this.yearLabel,
    this.subtitle,
    this.minHeight = 0,
  });

  final String title;

  /// Free-text year label ("Year 1", "Prep", "Specialist"…); non-year labels
  /// get the neutral style.
  final String yearLabel;
  final String? subtitle;

  /// Optional minimum height (the mockup uses 228 pt including status bar).
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final style = YearLevelColors.styleForLabel(yearLabel, colors);
    final top = MediaQuery.paddingOf(context).top;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style.fill,
          borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(AppTokens.headerRadius)),
          border: style.needsBorder
              ? Border(
                  bottom:
                      BorderSide(color: YearLevelColors.borderColor(colors)))
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, top + 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(title,
                    style:
                        AppTypography.largeTitle.copyWith(color: style.onFill)),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    style: AppTypography.subheadline.copyWith(
                        color: style.onFill, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
