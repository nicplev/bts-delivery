import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

export '../../app/theme/app_tokens.dart';

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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AppTokens.cardRadius));
    final content = Padding(padding: padding, child: child);
    final panel = Material(
      color: tone?.tint ?? AppTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AppTokens.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
    return margin == null ? panel : Padding(padding: margin!, child: panel);
  }
}

class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    this.tone = AppTone.blue,
    this.size = 40,
  });

  final IconData icon;
  final AppTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.tint,
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        ),
        child: Icon(
          icon,
          color: tone.ink,
          size: size >= 60 ? 30 : 20,
        ),
      ),
    );
  }
}

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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(AppTokens.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: tone.ink, size: 15),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tone.ink,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Text(title, style: Theme.of(context).textTheme.titleLarge);
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

class AppGroupedList extends StatelessWidget {
  const AppGroupedList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index != 0) const Divider(height: 1, indent: 16, endIndent: 16),
            children[index],
          ],
        ],
      ),
    );
  }
}
