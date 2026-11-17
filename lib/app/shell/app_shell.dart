import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/saved_edits_review.dart';
import '../../widgets/design/design.dart';

/// Main tabs: content scrolls beneath a floating glass tab bar.
///
/// The body extends behind the bar; its `MediaQuery` bottom padding (and view
/// padding, so nested `Scaffold` FABs clear it) covers the bar, the saved-edits
/// banner and the home indicator.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const tabs = [
    AppTabItem(
      label: 'Deliveries',
      icon: AppIcons.deliveries,
      selectedIcon: AppIcons.deliveriesSolid,
    ),
    AppTabItem(
      label: 'Schools',
      icon: AppIcons.schools,
      selectedIcon: AppIcons.schoolsSolid,
    ),
    AppTabItem(
      label: 'Profile',
      icon: AppIcons.profile,
      selectedIcon: AppIcons.profileSolid,
    ),
  ];

  static const _paths = ['/home', '/schools', '/profile'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _getCurrentIndex(context);
    final viewBottom = MediaQuery.viewPaddingOf(context).bottom;
    // Sit just above the home indicator (26 pt from the edge on a 34 pt inset).
    final barBottom = math.max(12.0, viewBottom - 8);

    return Scaffold(
      extendBody: true,
      body: Builder(builder: (context) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            viewPadding: media.viewPadding.copyWith(
                bottom:
                    math.max(media.viewPadding.bottom, media.padding.bottom)),
          ),
          child: child,
        );
      }),
      bottomNavigationBar: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              AppTokens.gutter, 4, AppTokens.gutter, barBottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SavedEditsBanner(),
              const SizedBox(height: 8),
              AppGlassTabBar(
                items: tabs,
                selectedIndex: currentIndex,
                onSelected: (index) => context.go(_paths[index]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/schools')) {
      return 1;
    }
    if (location.startsWith('/profile')) {
      return 2;
    }
    return 0;
  }
}
