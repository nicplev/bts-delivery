import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/saved_edits_review.dart';
import '../theme/brand_colors.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _getCurrentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SavedEditsBanner(),
          NavigationBar(
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
              _buildNavDestination(
                index: 0,
                currentIndex: currentIndex,
                icon: Icons.local_shipping_outlined,
                selectedIcon: Icons.local_shipping,
                label: 'Deliveries',
                color: BrandColors.kakaBlue,
              ),
              _buildNavDestination(
                index: 1,
                currentIndex: currentIndex,
                icon: Icons.school_outlined,
                selectedIcon: Icons.school,
                label: 'Schools',
                color: BrandColors.kakaGreen,
              ),
              _buildNavDestination(
                index: 2,
                currentIndex: currentIndex,
                icon: Icons.person_outlined,
                selectedIcon: Icons.person,
                label: 'Profile',
                color: BrandColors.kakaPink,
              ),
            ],
          ),
        ],
      ),
    );
  }

  NavigationDestination _buildNavDestination({
    required int index,
    required int currentIndex,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required Color color,
  }) {
    final isSelected = index == currentIndex;
    return NavigationDestination(
      icon: Icon(
        icon,
        color: isSelected ? color : BrandColors.textTertiary,
      ),
      selectedIcon: Icon(selectedIcon, color: color),
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
    return 0; // Default to deliveries
  }
}
