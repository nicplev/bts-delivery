import 'dart:math' as math;

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
/// [actions] (glass buttons / [AppGlassStatus]) on the trailing side, and an
/// optional small centred [title] with a [subtitle] under it.
///
/// Pair with `Scaffold(extendBodyBehindAppBar: true)` and put an
/// [AppLargeTitle] (or [AppYearHeader]) at the top of the scrolling content so
/// the title scrolls with it. Back uses go_router (`context.pop()`), falling
/// back to `Navigator.maybePop`.
///
/// With a [subtitle] the bar grows with its text (large text sizes), so place
/// it above the content in a `Column` rather than as `Scaffold.appBar`, whose
/// height is fixed to [preferredSize].
///
/// As `Scaffold.appBar` it draws a scroll-edge fade under its buttons: a strip
/// over the status bar and the bar that fades from the canvas colour to
/// transparent, so scrolled content never collides with the glass buttons.
/// On a screen that starts with an [AppYearHeader], pass the header's key as
/// [yearHeaderKey] and its [yearLabel]: while the header is beneath the bar
/// the fade is hidden and the glass glyphs take the header's label colour.
class AppNavBar extends StatefulWidget implements PreferredSizeWidget {
  const AppNavBar({
    super.key,
    this.actions = const [],
    this.showBack,
    this.onBack,
    this.backLabel = 'Back',
    this.backTooltip,
    this.backEnabled = true,
    this.title,
    this.subtitle,
    this.yearHeaderKey,
    this.yearLabel,
  });

  /// Trailing widgets, spaced 8 pt (e.g. [AppGlassIconButton]).
  final List<Widget> actions;

  /// Force the back button on/off; by default shown when a route can be popped.
  final bool? showBack;

  /// Overrides the back behaviour.
  final VoidCallback? onBack;

  /// Semantics label of the back button ("Back" or "Back to Oakfield Primary").
  final String backLabel;

  /// Optional long-press / hover tooltip on the back button.
  final String? backTooltip;

  /// Disables the back button (e.g. while saving).
  final bool backEnabled;

  /// Optional small centred title (most screens use [AppLargeTitle] instead).
  final String? title;

  /// Muted line (up to two lines) under [title], e.g. the school and visit.
  final String? subtitle;

  /// Key of the [AppYearHeader] at the top of the content, if any.
  final GlobalKey? yearHeaderKey;

  /// Year label of that header ("Year 1"…), which picks the glyph colour.
  final String? yearLabel;

  static const double height = AppTokens.navButtonSize + 8;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  State<AppNavBar> createState() => _AppNavBarState();
}

class _AppNavBarState extends State<AppNavBar> {
  ScrollNotificationObserverState? _observer;

  /// Whether the year header is still beneath the bar.
  bool _overHeader = true;

  @override
  void initState() {
    super.initState();
    if (widget.yearHeaderKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(AppNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.yearHeaderKey != oldWidget.yearHeaderKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ScrollNotification notification) {
    if (widget.yearHeaderKey == null) return;
    if (notification.metrics.axis != Axis.vertical) return;
    _measure();
  }

  /// Compares the header's bottom edge with the bar's.
  void _measure() {
    if (!mounted) return;
    final key = widget.yearHeaderKey;
    var over = false;
    final header = key?.currentContext?.findRenderObject();
    final bar = context.findRenderObject();
    if (header is RenderBox &&
        header.attached &&
        header.hasSize &&
        bar is RenderBox &&
        bar.hasSize) {
      final headerBottom =
          header.localToGlobal(Offset(0, header.size.height)).dy;
      final barBottom = bar.localToGlobal(Offset(0, bar.size.height)).dy;
      over = headerBottom > barBottom;
    }
    if (over != _overHeader) setState(() => _overHeader = over);
  }

  @override
  Widget build(BuildContext context) {
    final back = widget.showBack ?? _canGoBack(context);
    final colors = AppPalette.of(context);
    final actions = widget.actions;
    final backLabel = widget.backLabel;
    final backTooltip = widget.backTooltip;
    final backEnabled = widget.backEnabled;
    final onBack = widget.onBack;
    final title = widget.title;
    final subtitle = widget.subtitle;
    final headerStyle = widget.yearHeaderKey != null && widget.yearLabel != null
        ? YearLevelColors.styleForLabel(widget.yearLabel!, colors)
        : null;
    final overHeader = widget.yearHeaderKey != null && _overHeader;
    final leading = back
        ? AppGlassIconButton(
            icon: AppIcons.back,
            semanticLabel: backLabel,
            tooltip: backTooltip,
            onPressed:
                !backEnabled ? null : onBack ?? () => appNavigateBack(context),
          )
        : null;
    final trailing = actions.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                actions[i],
              ],
            ],
          );
    final titleText = title == null
        ? null
        : Semantics(
            header: true,
            child: Text(title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headline.copyWith(color: colors.ink)),
          );
    if (subtitle != null) {
      // Grows with the text; the sides reserve one button each so the title
      // stays centred.
      const side = SizedBox(width: AppTokens.navButtonSize);
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.gutter, 4, AppTokens.gutter, 8),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: AppTokens.navButtonSize),
            child: Row(
              children: [
                leading ?? side,
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (titleText != null) titleText,
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.footnote
                            .copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ?? side,
              ],
            ),
          ),
        ),
      );
    }
    Widget bar = SafeArea(
      bottom: false,
      child: SizedBox(
        height: AppNavBar.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.gutter, vertical: 4),
          child: NavigationToolbar(
            leading: leading,
            middle: titleText,
            trailing: trailing,
          ),
        ),
      ),
    );
    if (overHeader && headerStyle != null && headerStyle.isYear) {
      bar = AppGlassTint.forYearHeader(headerStyle, child: bar);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: overHeader ? 0 : 1,
              duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: _ScrollEdgeFade(
                color: colors.canvas,
                statusBar: MediaQuery.paddingOf(context).top,
              ),
            ),
          ),
        ),
        bar,
      ],
    );
  }
}

/// Canvas colour, opaque over the status bar, fading to transparent at the
/// bottom of the nav bar.
class _ScrollEdgeFade extends StatelessWidget {
  const _ScrollEdgeFade({required this.color, required this.statusBar});

  final Color color;
  final double statusBar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      final opaqueTo = height > 0 && height.isFinite
          ? (statusBar / height).clamp(0.0, 0.9)
          : 0.0;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color,
              color,
              color.withValues(alpha: 0.8),
              color.withValues(alpha: 0),
            ],
            stops: [
              0,
              opaqueTo * 0.8,
              opaqueTo + (1 - opaqueTo) * 0.5,
              1,
            ],
          ),
        ),
      );
    });
  }
}

/// A large title that wraps only between words: the text scale is capped at
/// [maxScaleFactor] and, when a single word is still wider than the line,
/// the whole title scales down so that word fits.
class AppTitleText extends StatelessWidget {
  const AppTitleText(
    this.text, {
    super.key,
    required this.style,
    this.maxScaleFactor = 1.3,
  });

  final String text;
  final TextStyle style;
  final double maxScaleFactor;

  @override
  Widget build(BuildContext context) {
    final scaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: maxScaleFactor);
    final direction = Directionality.of(context);
    // Measure with the style the Text will actually use.
    final measureStyle = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(builder: (context, constraints) {
      var effective = scaler;
      final maxWidth = constraints.maxWidth;
      if (maxWidth.isFinite && maxWidth > 0) {
        var widest = 0.0;
        for (final word in text.split(RegExp(r'\s+'))) {
          if (word.isEmpty) continue;
          final painter = TextPainter(
            text: TextSpan(text: word, style: measureStyle),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          widest = math.max(widest, painter.width);
          painter.dispose();
        }
        if (widest > maxWidth) {
          final base = style.fontSize ?? 14;
          final factor = scaler.scale(base) / base * (maxWidth / widest) * 0.98;
          effective = TextScaler.linear(factor);
        }
      }
      return Text(text, style: style, textScaler: effective);
    });
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
            child: AppTitleText(title,
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
                child: AppTitleText(title,
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
