import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/saved_edits_review.dart';
import '../../widgets/design/design.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _getCurrentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SavedEditsBanner(),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTokens.surface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppTokens.outline),
                boxShadow: AppTokens.panelShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: NavigationBar(
                  onDestinationSelected: (index) {
                    switch (index) {
                      case 0:
                        context.go('/home');
                        break;
                      case 1:
                        context.go('/schools');
                        break;
                      case 2:
                        context.go('/profile');
                        break;
                    }
                  },
                  selectedIndex: currentIndex,
                  destinations: [
                    _destination(
                      icon: Icons.local_shipping_outlined,
                      selectedIcon: Icons.local_shipping,
                      label: 'Deliveries',
                      tone: AppTone.blue,
                    ),
                    _destination(
                      icon: Icons.school_outlined,
                      selectedIcon: Icons.school,
                      label: 'Schools',
                      tone: AppTone.green,
                    ),
                    _destination(
                      icon: Icons.person_outline_rounded,
                      selectedIcon: Icons.person_rounded,
                      label: 'Profile',
                      tone: AppTone.pink,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  NavigationDestination _destination({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required AppTone tone,
  }) {
    return NavigationDestination(
      icon: Icon(icon, color: AppTokens.muted),
      selectedIcon: Icon(selectedIcon, color: tone.ink),
      label: label,
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
