import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_providers.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/staff_link_screen.dart';
import '../shell/app_shell.dart';
import '../../screens/main/deliveries_screen.dart';
import '../../screens/forms/add_edit_delivery_screen.dart';
import '../../screens/main/schools_screen.dart';
import '../../screens/main/school_hub_screen.dart';
import '../../screens/forms/classrooms_screen.dart';
import '../../screens/forms/classroom_detail_screen.dart';
import '../../screens/forms/consumables_screen.dart';
import '../../screens/forms/bulk_import_screen.dart';
import '../../screens/forms/schools_bulk_import_screen.dart';
import '../../screens/admin/staff_management_screen.dart';
import '../../screens/admin/school_staff_allocation_screen.dart';
import '../../screens/admin/checklist_management_screen.dart';
import '../../screens/admin/pre_delivery_checklist_management_screen.dart';
import '../../screens/admin/season_export_screen.dart';
import '../../screens/main/profile_screen.dart';
import '../../models/school.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Custom page transition for bottom navigation tabs (fade transition)
Page<dynamic> _buildPageWithFadeTransition({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
  );
}

/// Custom page transition for forward navigation (slide from right)
Page<dynamic> _buildPageWithSlideTransition({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeInOutCubic;

      var tween = Tween(begin: begin, end: end).chain(
        CurveTween(curve: curve),
      );

      return SlideTransition(
        position: animation.drive(tween),
        child: child,
      );
    },
  );
}

class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(this._ref) {
    _ref.listen(authStateProvider, (previous, next) {
      // Only notify if the auth state actually changed (logged in/out)
      if (previous?.value?.uid != next.value?.uid) {
        notifyListeners();
      }
    });
    _ref.listen(currentStaffProvider, (previous, next) {
      // Only notify if staff link status changed
      if (previous?.value?.id != next.value?.id) {
        notifyListeners();
      }
    });
    _ref.listen(currentUserProvider, (previous, next) {
      // Only notify if user role changed or user loaded for first time
      if (previous?.value?.role != next.value?.role ||
          (previous?.value == null && next.value != null)) {
        notifyListeners();
      }
    });
  }

  final Ref _ref;
}

// Cache the router to prevent recreation
GoRouter? _cachedRouter;

final appRouterProvider = Provider<GoRouter>((ref) {
  // If router already exists, return it
  if (_cachedRouter != null) {
    return _cachedRouter!;
  }

  final notifier = GoRouterRefreshNotifier(ref);

  _cachedRouter = GoRouter(
    refreshListenable: notifier,
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: '/login',
    redirect: (context, state) {
      // Read the latest values from providers
      final authState = ref.read(authStateProvider);
      final currentStaff = ref.read(currentStaffProvider);
      final currentUser = ref.read(currentUserProvider);

      final authStateValue = authState.value;
      final currentStaffValue = currentStaff.value;
      final currentUserValue = currentUser.value;
      final userLoading = currentUser.isLoading;

      final isLoggedIn = authStateValue != null;
      final hasStaff = currentStaffValue != null;
      final isAdmin = currentUserValue?.isAdmin ?? false;

      final isLoginPage = state.matchedLocation == '/login';
      final isStaffLinkPage = state.matchedLocation == '/staff-link';

      // Debug logging
      if (kDebugMode) {
        debugPrint('Router redirect check:');
        debugPrint('  - isLoggedIn: $isLoggedIn');
        debugPrint('  - hasStaff: $hasStaff');
        debugPrint('  - userLoading: $userLoading');
        debugPrint('  - isAdmin: $isAdmin');
        debugPrint('  - currentUser: $currentUserValue');
        debugPrint('  - location: ${state.matchedLocation}');
        debugPrint('  - fullPath: ${state.fullPath}');
        debugPrint('  - uri: ${state.uri}');
      }

      // Not logged in -> go to login
      if (!isLoggedIn) {
        return isLoginPage ? null : '/login';
      }

      // If user is logged in but still on login page, redirect immediately
      // even if user document is still loading
      if (isLoggedIn && isLoginPage) {
        // Default to /schools while loading, will re-redirect if needed once loaded
        return '/schools';
      }

      // Wait for user document to load before redirecting to other pages
      if (userLoading) {
        return null; // Don't redirect while loading
      }

      // Admin users skip staff linking and go directly to schools
      if (isAdmin) {
        if (isLoginPage || isStaffLinkPage) {
          return '/schools';
        }
        return null;
      }

      // Allow access to main app routes even without staff link for authenticated users
      final allowedRoutesWithoutStaff = ['/schools', '/home', '/profile'];
      final isAllowedRoute = allowedRoutesWithoutStaff.any((route) => state.matchedLocation.startsWith(route));

      // Regular users need staff linking, but allow access to main app routes
      if (!hasStaff && !isAdmin && !isAllowedRoute) {
        return isStaffLinkPage ? null : '/staff-link';
      }

      // Logged in with staff but on auth pages -> go to schools
      if (isLoggedIn && hasStaff && (isLoginPage || isStaffLinkPage)) {
        return '/schools';
      }

      // Fallback: if user is logged in and not on login page, allow access to main app
      // This prevents getting stuck on staff-link page
      if (isLoggedIn && !isLoginPage) {
        return null; // Allow access to the current route
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/login',
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildPageWithFadeTransition(
          context: context,
          state: state,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/staff-link',
        pageBuilder: (context, state) => _buildPageWithSlideTransition(
          context: context,
          state: state,
          child: const StaffLinkScreen(),
        ),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Bottom nav routes - use fade transitions
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _buildPageWithFadeTransition(
              context: context,
              state: state,
              child: const DeliveriesScreen(),
            ),
          ),
          GoRoute(
            path: '/schools',
            pageBuilder: (context, state) => _buildPageWithFadeTransition(
              context: context,
              state: state,
              child: const SchoolsScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => _buildPageWithFadeTransition(
              context: context,
              state: state,
              child: const ProfileScreen(),
            ),
            routes: [
              // Sub-routes use slide transitions
              GoRoute(
                path: 'staff',
                pageBuilder: (context, state) => _buildPageWithSlideTransition(
                  context: context,
                  state: state,
                  child: const StaffManagementScreen(),
                ),
              ),
              GoRoute(
                path: 'checklist',
                pageBuilder: (context, state) => _buildPageWithSlideTransition(
                  context: context,
                  state: state,
                  child: const ChecklistManagementScreen(),
                ),
              ),
              GoRoute(
                path: 'pre-delivery-checklist',
                pageBuilder: (context, state) => _buildPageWithSlideTransition(
                  context: context,
                  state: state,
                  child: const PreDeliveryChecklistManagementScreen(),
                ),
              ),
              GoRoute(
                path: 'season-export',
                pageBuilder: (context, state) => _buildPageWithSlideTransition(
                  context: context,
                  state: state,
                  child: const SeasonExportScreen(),
                ),
              ),
            ],
          ),

          // Detail routes - use slide transitions
          GoRoute(
            path: '/deliveries/add',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: const AddEditDeliveryScreen(),
            ),
          ),
          GoRoute(
            path: '/deliveries/:id/edit',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: AddEditDeliveryScreen(
                deliveryId: state.pathParameters['id'],
              ),
            ),
          ),
          GoRoute(
            path: '/schools/bulk-import',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: const SchoolsBulkImportScreen(),
            ),
          ),
          GoRoute(
            path: '/schools/:id',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: SchoolHubScreen(
                schoolId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/schools/:id/staff-allocation',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: SchoolStaffAllocationScreen(
                school: state.extra as School,
              ),
            ),
          ),
          GoRoute(
            path: '/schools/:schoolId/year/:yearLevelId/classrooms',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: ClassroomsScreen(
                schoolId: state.pathParameters['schoolId']!,
                yearLevelId: state.pathParameters['yearLevelId']!,
              ),
            ),
          ),
          GoRoute(
            path:
                '/schools/:schoolId/year/:yearLevelId/classrooms/:classroomId',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: ClassroomDetailScreen(
                schoolId: state.pathParameters['schoolId']!,
                yearLevelId: state.pathParameters['yearLevelId']!,
                classroomId: state.pathParameters['classroomId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/schools/:schoolId/consumables',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: ConsumablesScreen(
                schoolId: state.pathParameters['schoolId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/schools/:schoolId/bulk-import',
            pageBuilder: (context, state) => _buildPageWithSlideTransition(
              context: context,
              state: state,
              child: BulkImportScreen(
                schoolId: state.pathParameters['schoolId']!,
                schoolName: state.uri.queryParameters['schoolName'] ?? 'School',
              ),
            ),
          ),
        ],
      ),
    ],
  );

  return _cachedRouter!;
});