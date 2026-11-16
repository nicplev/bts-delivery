import 'package:flutter/material.dart';
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
import '../../models/delivery_visit.dart';
import '../../providers/delivery_visit_provider.dart';
import '../../widgets/delivery_visit_gate.dart';

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
      if (previous?.valueOrNull?.uid != next.valueOrNull?.uid) {
        notifyListeners();
      }
    });
    _ref.listen(currentStaffProvider, (previous, next) {
      if (previous?.valueOrNull != next.valueOrNull ||
          previous?.isLoading != next.isLoading ||
          previous?.hasError != next.hasError) {
        notifyListeners();
      }
    });
  }

  final Ref _ref;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = GoRouterRefreshNotifier(ref);

  String? requireTemplateAccess(BuildContext context, GoRouterState state) {
    if (ref.read(canEditSchoolDataProvider)) return null;
    return schoolWorkPath(state.pathParameters['schoolId']!);
  }

  final router = GoRouter(
    refreshListenable: notifier,
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: '/login',
    redirect: (context, state) {
      final user = ref.read(authStateProvider).valueOrNull;
      final staff = ref.read(currentStaffProvider);
      final onLogin = state.matchedLocation == '/login';
      final onStaffLink = state.matchedLocation == '/staff-link';

      if (user == null) return onLogin ? null : '/login';
      if (staff.isLoading && !staff.hasValue) return null;
      if (staff.hasError) {
        return state.matchedLocation == '/home' ? null : '/home';
      }
      final linked = staff.valueOrNull?.uid == user.uid;
      if (!linked) return onStaffLink ? null : '/staff-link';
      if (onLogin || onStaffLink) return '/home';
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
          ShellRoute(
            builder: (context, state, child) {
              final visit = DeliveryVisit(
                deliveryId: state.pathParameters['deliveryId']!,
                schoolId: state.pathParameters['schoolId']!,
              );
              return ProviderScope(
                key: ValueKey(visit),
                overrides: [
                  activeDeliveryVisitProvider.overrideWithValue(visit)
                ],
                child: DeliveryVisitGate(visit: visit, child: child),
              );
            },
            routes: [
              GoRoute(
                path: '/deliveries/:deliveryId/schools/:schoolId',
                pageBuilder: (context, state) => _buildPageWithSlideTransition(
                  context: context,
                  state: state,
                  child: SchoolHubScreen(
                    schoolId: state.pathParameters['schoolId']!,
                    deliveryId: state.pathParameters['deliveryId']!,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'year/:yearLevelId/classrooms',
                    pageBuilder: (context, state) =>
                        _buildPageWithSlideTransition(
                      context: context,
                      state: state,
                      child: ClassroomsScreen(
                        schoolId: state.pathParameters['schoolId']!,
                        yearLevelId: state.pathParameters['yearLevelId']!,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: ':classroomId',
                        pageBuilder: (context, state) =>
                            _buildPageWithSlideTransition(
                          context: context,
                          state: state,
                          child: ClassroomDetailScreen(
                            schoolId: state.pathParameters['schoolId']!,
                            yearLevelId: state.pathParameters['yearLevelId']!,
                            classroomId: state.pathParameters['classroomId']!,
                            deliveryId: state.pathParameters['deliveryId'],
                          ),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'consumables',
                    pageBuilder: (context, state) =>
                        _buildPageWithSlideTransition(
                      context: context,
                      state: state,
                      child: ConsumablesScreen(
                        schoolId: state.pathParameters['schoolId']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
            redirect: requireTemplateAccess,
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
            redirect: requireTemplateAccess,
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
            redirect: requireTemplateAccess,
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
            redirect: requireTemplateAccess,
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

  ref.onDispose(() {
    router.dispose();
    notifier.dispose();
  });
  return router;
});
