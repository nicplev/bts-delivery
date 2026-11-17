import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import 'app_icons.dart';
import 'glass.dart';

/// Opaque content card: surface, radius 20, no border or shadow (outline in
/// high contrast). [tone] tints it (neutral grey or warning amber).
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.tone,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final AppTone? tone;

  /// Makes the whole card tappable (ripple-free highlight).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AppTokens.cardRadius));
    final colors = AppPalette.of(context);
    final content = Padding(padding: padding, child: child);
    final panel = Material(
      color: tone?.tintOn(colors) ?? colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: colors.highContrast
            ? BorderSide(color: colors.outline)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory,
              highlightColor: colors.fill,
              child: content,
            ),
    );
    return margin == null ? panel : Padding(padding: margin!, child: panel);
  }
}

/// Light-grey rounded square with an ink glyph (sizes ≈ 29, 40, 48).
/// Use [AppIconTile.warning] for the amber variant.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    this.tone = AppTone.neutral,
    this.size = 40,
  });

  /// Amber tile with a dark amber glyph (something needs a decision).
  const AppIconTile.warning({super.key, required this.icon, this.size = 40})
      : tone = AppTone.warning;

  final IconData icon;
  final AppTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size <= 32
        ? 7.0
        : size >= 46
            ? 14.0
            : AppTokens.controlRadius;
    final glyph = size <= 32
        ? 18.0
        : size >= 60
            ? 30.0
            : size >= 46
                ? 26.0
                : 22.0;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.tintFor(context),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(icon, color: tone.inkFor(context), size: glyph),
      ),
    );
  }
}

/// Section label above a card: 13 pt semibold muted (e.g. "Next visit").
/// A [trailing] control moves under the label at large text / narrow width.
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.text, {super.key, this.trailing, this.color});

  final String text;

  /// Optional widget on the right (e.g. an [AppStatusPill]).
  final Widget? trailing;

  /// Overrides the muted colour (e.g. warning ink inside a warning card).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final label = Semantics(
      header: true,
      child: Text(
        text,
        style: AppTypography.footnote.copyWith(
          fontWeight: FontWeight.w600,
          color: color ?? AppPalette.of(context).muted,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: trailing == null
          ? label
          : LayoutBuilder(builder: (context, constraints) {
              if (appStackTrailing(context, constraints)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, const SizedBox(height: 8), trailing!],
                );
              }
              return Row(children: [
                Expanded(child: label),
                const SizedBox(width: 12),
                trailing!,
              ]);
            }),
    );
  }
}

/// Whether a trailing control should move under its text instead of sharing
/// the line: at large text sizes or in a narrow (< 240 pt) or unbounded width.
bool appStackTrailing(BuildContext context, BoxConstraints constraints) =>
    !constraints.hasBoundedWidth ||
    constraints.maxWidth < 240 ||
    MediaQuery.textScalerOf(context).scale(17) > 24;

/// Section title with an optional trailing action that wraps below the title
/// on narrow or large-text layouts.
class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
    if (trailing == null) return heading;

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
        if (!constraints.hasBoundedWidth ||
            constraints.maxWidth < 330 ||
            largeText) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 8), trailing!],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 8),
            trailing!
          ],
        );
      },
    );
  }
}

/// A card of rows separated by inset hairlines.
///
/// [separatorIndent] lines the separator up with the row text: 16 for plain
/// rows, 57 for rows with a 29 pt icon tile, 64 for rows with a 36 pt badge.
class AppGroupedList extends StatelessWidget {
  const AppGroupedList({
    super.key,
    required this.children,
    this.separatorIndent = 16,
    this.margin,
  });

  final List<Widget> children;
  final double separatorIndent;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final separator = AppPalette.of(context).separator;
    return AppPanel(
      padding: EdgeInsets.zero,
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index != 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: separatorIndent,
                color: separator,
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// A list row: optional leading (an [icon] in a 29 pt tile, or any [leading]
/// such as a year badge), title, subtitle, trailing detail text, trailing
/// widget and chevron. Min height 52 (68 with a subtitle). The whole row is
/// tappable with a ripple-free highlight when [onTap] is set.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.detail,
    this.trailing,
    this.onTap,
    this.showChevron,
    this.semanticLabel,
    this.titleStyle,
  });

  final String title;
  final String? subtitle;

  /// Shown in a 29 pt [AppIconTile]. Ignored when [leading] is set.
  final IconData? icon;
  final Widget? leading;

  /// Muted text before the trailing widget ("2 items").
  final String? detail;

  /// E.g. an [AppStatusRing] or a `Switch`.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Defaults to `onTap != null`.
  final bool? showChevron;

  /// Replaces the merged title/subtitle/detail label for screen readers.
  final String? semanticLabel;

  /// Overrides the 17 pt title style (e.g. semibold).
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final lead =
        leading ?? (icon == null ? null : AppIconTile(icon: icon!, size: 29));
    final chevron = showChevron ?? onTap != null;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: subtitle == null ? 52 : 68),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: LayoutBuilder(builder: (context, constraints) {
          final detailMaxWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth * 0.6
              : double.infinity;
          return Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: titleStyle ??
                            AppTypography.body.copyWith(color: colors.ink)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: AppTypography.subheadline
                              .copyWith(color: colors.muted)),
                  ],
                ),
              ),
              if (detail != null) ...[
                const SizedBox(width: 8),
                // Sized to its text (up to 60 % of the row) so the value always
                // sits at the trailing edge, whatever the title's length.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: detailMaxWidth),
                  child: Text(
                    detail!,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(color: colors.muted),
                  ),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (chevron) ...[
                const SizedBox(width: 6),
                ExcludeSemantics(
                  child:
                      Icon(AppIcons.chevron, size: 16, color: colors.chevron),
                ),
              ],
            ],
          );
        }),
      ),
    );
    if (onTap == null) {
      return semanticLabel == null
          ? row
          : Semantics(
              container: true,
              label: semanticLabel,
              excludeSemantics: true,
              child: row,
            );
    }
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      excludeChildSemantics: semanticLabel != null,
      pressedColor: colors.fill,
      child: row,
    );
  }
}

/// Chevron that points down when collapsed and up when [expanded]
/// (rotation respects reduce motion).
class AppDisclosureChevron extends StatelessWidget {
  const AppDisclosureChevron({super.key, required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        child: Icon(AppIcons.chevronDown,
            size: 18, color: AppPalette.of(context).chevron),
      ),
    );
  }
}

/// A ripple-free, collapsed-by-default row (optional [leading] / [icon],
/// title, subtitle, chevron) that shows [children] below it when expanded.
/// Use inside an opaque card; it carries the expanded semantics state.
class AppDisclosure extends StatefulWidget {
  const AppDisclosure({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.leading,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.childrenPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.initiallyExpanded = false,
  });

  final String title;
  final String? subtitle;

  /// Shown in a 29 pt [AppIconTile]. Ignored when [leading] is set.
  final IconData? icon;
  final Widget? leading;
  final List<Widget> children;

  /// Padding of the header row.
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry childrenPadding;
  final bool initiallyExpanded;

  @override
  State<AppDisclosure> createState() => _AppDisclosureState();
}

class _AppDisclosureState extends State<AppDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final lead = widget.leading ??
        (widget.icon == null
            ? null
            : AppIconTile(icon: widget.icon!, size: 29));
    final header = Semantics(
      expanded: _expanded,
      child: AppPressable(
        onTap: () => setState(() => _expanded = !_expanded),
        pressedColor: colors.fill,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: widget.subtitle == null ? 52 : 68),
          child: Padding(
            padding: widget.padding,
            child: Row(
              children: [
                if (lead != null) ...[lead, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style:
                              AppTypography.body.copyWith(color: colors.ink)),
                      if (widget.subtitle != null)
                        Text(widget.subtitle!,
                            style: AppTypography.subheadline
                                .copyWith(color: colors.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AppDisclosureChevron(expanded: _expanded),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (_expanded)
          Padding(
            padding: widget.childrenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}
