import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import 'glass.dart';

/// One destination of [AppGlassTabBar].
@immutable
class AppTabItem {
  const AppTabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;

  /// Outline icon (unselected).
  final IconData icon;

  /// Solid icon (selected).
  final IconData selectedIcon;
}

/// Floating glass tab bar: 62 pt capsule, selected tab = solid icon on a grey
/// pill, 10 pt semibold labels. Each tab is a button with the selected state.
class AppGlassTabBar extends StatelessWidget {
  const AppGlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Tab labels follow the system text size up to a point (as on iOS).
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final height = math.max(AppTokens.tabBarHeight, scaler.scale(12) + 44);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Main',
      child: SizedBox(
        height: height,
        child: AppGlass(
          padding: const EdgeInsets.all(4),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: AppPressable(
                      key: ValueKey('app-tab-$i'),
                      onTap: () => onSelected(i),
                      selected: i == selectedIndex,
                      semanticLabel: items[i].label,
                      excludeChildSemantics: true,
                      child: _Tab(
                        item: items[i],
                        selected: i == selectedIndex,
                        colors: colors,
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
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

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.colors,
    required this.duration,
  });

  final AppTabItem item;
  final bool selected;
  final AppPalette colors;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? colors.ink : colors.muted;
    return AnimatedContainer(
      duration: duration,
      decoration: BoxDecoration(
        color: selected ? colors.fill : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.pillRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? item.selectedIcon : item.icon, size: 22, color: ink),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.tabLabel.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}
