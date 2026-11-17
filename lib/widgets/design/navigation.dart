import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// A large-title header that scrolls away with a control (e.g. a segmented
/// switch) under it that stays pinned directly below the transparent
/// [AppNavBar] — for the header slivers of a [NestedScrollView] (or any
/// vertical scroll view) under `Scaffold(extendBodyBehindAppBar: true)`.
///
/// [header] starts at the very top (pad it by the `MediaQuery` top padding);
/// [pinned] follows it and stops at [pinTop] (by default the `MediaQuery` top
/// padding: status bar + nav bar). Content laid out after this sliver starts
/// below the pinned control, so nothing scrolls beneath it; a short canvas
/// fade (a hairline in high contrast) separates it from the content, and the
/// nav area above it turns to the canvas colour as the header leaves.
///
/// When the pinned part would take more than a third of the viewport
/// (very large text on a small screen) it scrolls away with the header.
class AppPinnedControlSliver extends StatelessWidget {
  const AppPinnedControlSliver({
    super.key,
    required this.header,
    required this.pinned,
    this.pinTop,
  });

  final Widget header;

  /// Paint it on the canvas colour (it covers the content scrolling by).
  final Widget pinned;

  /// Where the control sticks; defaults to `MediaQuery.paddingOf.top`.
  final double? pinTop;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return _PinnedControlSliver(
      header: header,
      pinned: pinned,
      pinTop: pinTop ?? MediaQuery.paddingOf(context).top,
      canvas: colors.canvas,
      hairline: colors.highContrast ? colors.outline : null,
    );
  }
}

enum _PinnedSlot { header, pinned }

class _PinnedControlSliver
    extends SlottedMultiChildRenderObjectWidget<_PinnedSlot, RenderBox> {
  const _PinnedControlSliver({
    required this.header,
    required this.pinned,
    required this.pinTop,
    required this.canvas,
    required this.hairline,
  });

  final Widget header;
  final Widget pinned;
  final double pinTop;
  final Color canvas;
  final Color? hairline;

  @override
  Iterable<_PinnedSlot> get slots => _PinnedSlot.values;

  @override
  Widget? childForSlot(_PinnedSlot slot) => switch (slot) {
        _PinnedSlot.header => header,
        _PinnedSlot.pinned => pinned,
      };

  @override
  _RenderPinnedControlSliver createRenderObject(BuildContext context) =>
      _RenderPinnedControlSliver(
        pinTop: pinTop,
        canvas: canvas,
        hairline: hairline,
      );

  @override
  void updateRenderObject(
      BuildContext context, _RenderPinnedControlSliver renderObject) {
    renderObject
      ..pinTop = pinTop
      ..canvas = canvas
      ..hairline = hairline;
  }
}

class _RenderPinnedControlSliver extends RenderSliver
    with SlottedContainerRenderObjectMixin<_PinnedSlot, RenderBox> {
  _RenderPinnedControlSliver({
    required double pinTop,
    required Color canvas,
    required Color? hairline,
  })  : _pinTop = pinTop,
        _canvas = canvas,
        _hairline = hairline;

  /// Height of the fade under the pinned control.
  static const double _fade = 8;

  /// The nav area turns opaque over the header's last [_coverRamp] points.
  static const double _coverRamp = 24;

  double get pinTop => _pinTop;
  double _pinTop;
  set pinTop(double value) {
    if (value == _pinTop) return;
    _pinTop = value;
    markNeedsLayout();
  }

  Color get canvas => _canvas;
  Color _canvas;
  set canvas(Color value) {
    if (value == _canvas) return;
    _canvas = value;
    markNeedsPaint();
  }

  Color? get hairline => _hairline;
  Color? _hairline;
  set hairline(Color? value) {
    if (value == _hairline) return;
    _hairline = value;
    markNeedsPaint();
  }

  RenderBox? get _header => childForSlot(_PinnedSlot.header);
  RenderBox? get _pinned => childForSlot(_PinnedSlot.pinned);

  double _headerY = 0;
  double _pinnedY = 0;
  double _cover = 0;
  bool _stuck = false;

  /// Whether the control is currently pinning (false when too tall).
  bool get pins => _pins;
  bool _pins = true;

  @override
  void performLayout() {
    assert(constraints.axisDirection == AxisDirection.down,
        'AppPinnedControlSliver supports top-to-bottom scrolling only');
    final header = _header;
    final pinned = _pinned;
    final box = constraints.asBoxConstraints();
    header?.layout(box, parentUsesSize: true);
    pinned?.layout(box, parentUsesSize: true);
    final h1 = header?.size.height ?? 0;
    final h2 = pinned?.size.height ?? 0;
    final s = constraints.scrollOffset;
    final viewport = constraints.viewportMainAxisExtent;
    _pins = viewport.isFinite && _pinTop + h2 <= viewport / 3;
    _headerY = -s;
    if (!_pins) {
      final total = h1 + h2;
      final paintExtent = calculatePaintOffset(constraints, from: 0, to: total);
      _pinnedY = h1 - s;
      _stuck = false;
      _cover = 0;
      geometry = SliverGeometry(
        scrollExtent: total,
        paintExtent: paintExtent,
        maxPaintExtent: total,
        hitTestExtent: paintExtent,
        hasVisualOverflow: total > paintExtent || s > 0,
      );
      return;
    }
    // Only the part of the header above the pin line scrolls; the control
    // keeps its layout extent, so the content after it starts below it.
    final scrollExtent = math.max(0.0, h1 - _pinTop);
    _pinnedY = math.max(h1 - s, _pinTop);
    _stuck = s >= scrollExtent - 1e-6;
    _cover = scrollExtent <= 0
        ? 1
        : ((s - (scrollExtent - _coverRamp)) / _coverRamp).clamp(0.0, 1.0);
    final paintExtent =
        math.min(_pinnedY + h2, constraints.remainingPaintExtent);
    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      layoutExtent: paintExtent,
      maxPaintExtent: math.max(h1 + h2, paintExtent),
      maxScrollObstructionExtent: _pinTop + h2,
      hitTestExtent: paintExtent,
      hasVisualOverflow: true,
    );
  }

  double _positionOf(RenderObject child) =>
      identical(child, _pinned) ? _pinnedY : _headerY;

  @override
  double childMainAxisPosition(covariant RenderObject child) =>
      _positionOf(child);

  @override
  double childScrollOffset(covariant RenderObject child) =>
      identical(child, _pinned) ? (_header?.size.height ?? 0) : 0;

  @override
  void applyPaintTransform(covariant RenderObject child, Matrix4 transform) {
    transform.translateByDouble(0.0, _positionOf(child), 0.0, 1.0);
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final boxResult = BoxHitTestResult.wrap(result);
    for (final child in [_pinned, _header]) {
      if (child == null) continue;
      final y = _positionOf(child);
      if (mainAxisPosition < y || mainAxisPosition >= y + child.size.height) {
        continue;
      }
      // The header beneath the opaque nav area is not tappable.
      if (identical(child, _header) &&
          _cover >= 1 &&
          mainAxisPosition < _pinnedY) {
        continue;
      }
      final hit = boxResult.addWithPaintOffset(
        offset: Offset(0, y),
        position: Offset(crossAxisPosition, mainAxisPosition),
        hitTest: (result, position) =>
            child.hitTest(result, position: position),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final header = _header;
    final pinned = _pinned;
    if (header != null && _headerY + header.size.height > 0) {
      context.paintChild(header, offset + Offset(0, _headerY));
    }
    if (pinned == null) return;
    final width = constraints.crossAxisExtent;
    final canvas = context.canvas;
    if (_cover > 0 && _pinnedY > 0) {
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, width, _pinnedY),
        Paint()..color = _canvas.withValues(alpha: _canvas.a * _cover),
      );
    }
    if (_stuck) {
      final top = offset.dy + _pinnedY + pinned.size.height;
      final line = _hairline;
      if (line != null) {
        canvas.drawRect(
            Rect.fromLTWH(offset.dx, top - 1, width, 1), Paint()..color = line);
      } else {
        final rect = Rect.fromLTWH(offset.dx, top, width, _fade);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_canvas, _canvas.withValues(alpha: 0)],
            ).createShader(rect),
        );
      }
    }
    context.paintChild(pinned, offset + Offset(0, _pinnedY));
  }
}
