import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/design/design.dart';

/// Page frame shared by the Schools / Profile tabs, the admin screens and the
/// school import: a transparent nav bar with glass buttons, a large title that
/// scrolls with the content, and an optional floating primary [action].
///
/// Content is given either as [children] (laid out in one column with the
/// screen gutters) or as [slivers] for lists that need their own sliver (e.g.
/// a reorderable list). On wide screens the content is centred at [maxWidth].
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.navActions = const [],
    this.showBack,
    this.backLabel = 'Back',
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

  /// Screen-reader label of the back button ("Back to profile").
  final String backLabel;

  /// The one floating primary action (usually an [AppGlassPrimaryButton]).
  final Widget? action;

  final List<Widget> children;

  /// Replaces [children]; each sliver is padded by the page gutters.
  final List<Widget>? slivers;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final slivers = this.slivers;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppNavBar(
          actions: navActions, showBack: showBack, backLabel: backLabel),
      body: AppFloatingActionArea(
        action: action,
        child: LayoutBuilder(builder: (context, constraints) {
          final insets = AppInsets.scroll(context);
          final side =
              math.max(AppTokens.gutter, (constraints.maxWidth - maxWidth) / 2);
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
              SliverPadding(padding: EdgeInsets.only(bottom: insets.bottom)),
            ],
          );
        }),
      ),
    );
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
    return AppPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      excludeChildSemantics: true,
      child: const AppMenuCircle(),
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
