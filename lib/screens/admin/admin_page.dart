import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../widgets/design/design.dart';

/// Page frame shared by the Schools / Profile tabs, the admin screens and the
/// school import: a transparent nav bar with glass buttons, a large title that
/// scrolls with the content, and an optional floating primary [action].
///
/// Content is given either as [children] (laid out in one column with the
/// screen gutters) or as [slivers] for lists that need their own sliver (e.g.
/// a reorderable list). On wide screens the content is centred at [maxWidth].
class AdminPage extends StatefulWidget {
  const AdminPage({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.navActions = const [],
    this.showBack,
    this.action,
    this.children = const [],
    this.slivers,
    this.maxWidth = 700,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;

  /// Glass buttons on the trailing side of the nav bar.
  final List<Widget> navActions;

  /// Forces the glass back button on/off (default: shown when a route can pop).
  final bool? showBack;

  /// The one floating primary action (usually an [AppGlassPrimaryButton]).
  final Widget? action;

  final List<Widget> children;

  /// Replaces [children]; each sliver is padded by the page gutters.
  final List<Widget>? slivers;

  final double maxWidth;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  /// Keeps the scroll view (and its position) when the floating action
  /// appears or disappears: `AppFloatingActionArea` wraps the content in a
  /// `Stack` only while it has an action, which would otherwise rebuild it.
  final _contentKey = GlobalKey();

  /// Measured height of the floating action. `AppFloatingActionArea` reserves
  /// room for a one-line label; at large text sizes the label wraps, so the
  /// difference is added to the bottom of the scroll view.
  double _actionHeight = 0;

  void _onActionHeight(double height) {
    if (mounted && height != _actionHeight) {
      setState(() => _actionHeight = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final subtitle = widget.subtitle;
    final subtitleWidget = widget.subtitleWidget;
    final slivers = widget.slivers;
    final children = widget.children;
    final maxWidth = widget.maxWidth;
    final action = widget.action;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppNavBar(actions: widget.navActions, showBack: widget.showBack),
      body: AppFloatingActionArea(
        action: action == null
            ? null
            : _MeasureHeight(onHeight: _onActionHeight, child: action),
        child: LayoutBuilder(
            key: _contentKey,
            builder: (context, constraints) {
              final reserved = AppFloatingActionArea.reservedHeight(context);
              final overflow = action == null
                  ? 0.0
                  : math.max(
                      0.0,
                      _actionHeight +
                          AppTokens.floatingActionGap * 2 -
                          reserved);
              final insets = AppInsets.scroll(context, bottom: 24 + overflow);
              final side = math.max(
                  AppTokens.gutter, (constraints.maxWidth - maxWidth) / 2);
              EdgeInsets gutters(double top, double bottom) =>
                  EdgeInsets.fromLTRB(side, top, side, bottom);
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: gutters(insets.top, 16),
                    sliver: SliverToBoxAdapter(
                      child: AppLargeTitle(
                        title: title,
                        subtitle: subtitle,
                        subtitleWidget: subtitleWidget,
                      ),
                    ),
                  ),
                  if (slivers != null)
                    for (final sliver in slivers)
                      SliverPadding(padding: gutters(0, 0), sliver: sliver)
                  else
                    SliverPadding(
                      padding: gutters(0, 0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(children),
                      ),
                    ),
                  SliverPadding(
                      padding: EdgeInsets.only(bottom: insets.bottom)),
                ],
              );
            }),
      ),
    );
  }
}

/// Reports its child's laid-out height after each layout that changes it.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
          BuildContext context, _RenderMeasureHeight renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// A section label followed by its card, with the standard section gap above.
class AdminSection extends StatelessWidget {
  const AdminSection({
    super.key,
    required this.label,
    required this.child,
    this.first = false,
  });

  final String label;
  final Widget child;

  /// Drops the gap above (for the first section under the title).
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : AppTokens.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionLabel(label),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Centred loading spinner for page content.
class AdminLoading extends StatelessWidget {
  const AdminLoading({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
}

/// Opaque, in-card "more" control (44 pt target, grey circle, ink glyph) that
/// opens the per-item options.
class AdminOptionsButton extends StatelessWidget {
  const AdminOptionsButton({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      excludeChildSemantics: true,
      child: SizedBox.square(
        dimension: AppTokens.minTouchTarget,
        child: Center(
          child: DecoratedBox(
            decoration:
                BoxDecoration(color: colors.fill, shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(AppIcons.more, size: 18, color: colors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice in [showAdminActionSheet].
class AdminSheetAction<T> {
  const AdminSheetAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;

  /// Shown in the error colour (delete).
  final bool destructive;
}

/// Glass sheet listing [actions] as icon-tile rows; resolves to the chosen
/// action's value (null when dismissed).
Future<T?> showAdminActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<AdminSheetAction<T>> actions,
}) {
  return showAppGlassSheet<T>(
    context: context,
    title: title,
    builder: (sheetContext) {
      final colors = AppPalette.of(sheetContext);
      return SingleChildScrollView(
        child: AppGroupedList(
          separatorIndent: 57,
          children: [
            for (final action in actions)
              AppListRow(
                icon: action.icon,
                title: action.label,
                titleStyle: action.destructive
                    ? AppTypography.body.copyWith(color: colors.error)
                    : null,
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop(action.value),
              ),
          ],
        ),
      );
    },
  );
}

/// Full-width grey capsule with an error-coloured label (sign out).
class AdminDestructiveButton extends StatelessWidget {
  const AdminDestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: colors.error,
          minimumSize: const Size(44, AppTokens.primaryButtonHeight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

/// Destructive confirm button for dialogs (error fill).
ButtonStyle adminDestructiveStyle(BuildContext context) {
  final colors = AppPalette.of(context);
  return FilledButton.styleFrom(
    backgroundColor: colors.error,
    foregroundColor: colors.onError,
  );
}
