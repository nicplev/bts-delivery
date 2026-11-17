import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/delivery.dart';
import 'package:bts_delivery_app/models/pre_delivery_checklist_item.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/pre_delivery_checklist_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/repositories/deliveries_repository.dart';
import 'package:bts_delivery_app/screens/forms/add_edit_delivery_screen.dart';
import 'package:bts_delivery_app/screens/main/deliveries_screen.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
      'next visit is a hero card and later visits are rows that open the visit',
      (tester) async {
    final today = _today();
    await tester.pumpWidget(_app(_Repository(today)));
    await tester.pumpAndSettle();

    expect(find.text('Deliveries'), findsWidgets);
    expect(find.textContaining('· 2 visits'), findsOneWidget);
    expect(find.text('Next visit'), findsOneWidget);
    expect(find.text('9:00 AM · Visit 1'), findsOneWidget);
    expect(find.text('Oakfield Primary'), findsOneWidget);
    expect(find.text('Use Gate B near reception.'), findsOneWidget);
    expect(find.text('To complete'), findsOneWidget);
    expect(find.text('Later today'), findsOneWidget);
    expect(find.text('1:30 PM · Visit 2 · 2 pallets'), findsOneWidget);
    expect(find.text('Open visit'), findsOneWidget);
    // Drivers have no delivery management.
    expect(find.byTooltip('Manage delivery'), findsNothing);
    expect(find.byTooltip('Add delivery'), findsNothing);

    final row = find.byKey(const ValueKey('second'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riverside School'));
    await tester.pumpAndSettle();
    expect(find.text('Visit second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a later visit keeps its pre-delivery checklist in its options',
      (tester) async {
    final today = _today();
    await tester.pumpWidget(_app(_Repository(today)));
    await tester.pumpAndSettle();

    final options = find.byTooltip('Visit options for Riverside School');
    await tester.ensureVisible(options);
    await tester.pumpAndSettle();
    await tester.tap(options);
    await tester.pumpAndSettle();
    // Drivers only get the checklist entry.
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('Pre-delivery checklist · To complete'));
    await tester.pumpAndSettle();
    expect(find.text('Riverside School'), findsWidgets);
    expect(find.text('0 of 1 checked'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admins manage a visit and add deliveries from the nav bar',
      (tester) async {
    final today = _today();
    await tester.pumpWidget(_app(_Repository(today), isAdmin: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage delivery'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Manage staff'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete delivery?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add delivery'));
    await tester.pumpAndSettle();
    expect(find.text('Add delivery'), findsWidgets);
    expect(find.byType(AddEditDeliveryScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delivery options menu keeps the calendar entries',
      (tester) async {
    await tester.pumpWidget(_app(_Repository(_today())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delivery options'));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe to delivery calendar'), findsOneWidget);
    expect(find.text('Sync external calendar (legacy)'), findsOneWidget);
    await tester.tap(find.text('Sync external calendar (legacy)'));
    await tester.pumpAndSettle();
    expect(find.text('Sync to Apple Calendar'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today view fits 320 pt at 200 % text in dark high contrast',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(
      _Repository(_today()),
      isAdmin: true,
      textScale: 2,
      theme: AppTheme.highContrastDarkTheme,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final open = find.text('Open visit');
    await tester.ensureVisible(open);
    // Bring it out from under the floating nav buttons.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(open.hitTestable(), findsOneWidget);
    expect(tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(44));
    final row = find.byKey(const ValueKey('second'));
    await tester.scrollUntilVisible(row, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(
        find.byTooltip('Visit options for Riverside School'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Widget _app(
  _Repository repository, {
  bool isAdmin = false,
  double textScale = 1,
  ThemeData? theme,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const DeliveriesScreen()),
      GoRoute(
        path: '/deliveries/add',
        builder: (_, __) => const AddEditDeliveryScreen(),
      ),
      GoRoute(
        path: '/deliveries/:deliveryId/schools/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Visit ${state.pathParameters['deliveryId']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final today = repository.today;

  return ProviderScope(
    overrides: [
      deliveriesRepositoryProvider.overrideWithValue(repository),
      isAdminProvider.overrideWithValue(isAdmin),
      currentStaffProvider.overrideWith((_) => Stream.value(Staff(
            id: 'staff',
            name: 'Driver',
            role: isAdmin ? 'admin' : 'staff',
            assignedSchoolIds: const ['oakfield', 'riverside'],
            createdAt: today,
          ))),
      connectivityStatusProvider
          .overrideWith((_) => Stream.value(ConnectivityStatus.online)),
      evidenceUploadsProvider.overrideWith(
        (_) => Stream.value(
          const EvidenceUploadStatus(
            items: [],
            activeId: null,
            legacyReviewCount: 0,
            localError: false,
          ),
        ),
      ),
      deliveryChecklistStatusProvider
          .overrideWith((_, __) => const AsyncValue.data(false)),
      activePreDeliveryChecklistItemsProvider.overrideWith((_) => Stream.value([
            PreDeliveryChecklistItem(
              id: 'gate',
              title: 'Confirm the gate access',
              order: 0,
              createdAt: today,
            ),
          ])),
      deliveryCompletionsProvider
          .overrideWith((_, __) => Stream.value(const [])),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: theme ?? AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

class _Repository implements DeliveriesRepository {
  _Repository(this.today);

  final DateTime today;

  @override
  Stream<List<Delivery>> watchDeliveriesByDateRange(
    DateTime start,
    DateTime end, {
    List<String>? schoolIds,
  }) {
    if (today.isBefore(start) || !today.isBefore(end)) {
      return Stream.value(const []);
    }
    return Stream.value([
      Delivery(
        id: 'second',
        schoolId: 'riverside',
        schoolName: 'Riverside School',
        date: today,
        time: today.add(const Duration(hours: 13, minutes: 30)),
        palletCount: 2,
        createdAt: today,
      ),
      Delivery(
        id: 'first',
        schoolId: 'oakfield',
        schoolName: 'Oakfield Primary',
        date: today,
        time: today.add(const Duration(hours: 9)),
        palletCount: 4,
        notes: 'Use Gate B near reception.',
        createdAt: today,
      ),
    ]);
  }

  @override
  Future<Result<List<Staff>>> getAllStaff() async => const Result.success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
