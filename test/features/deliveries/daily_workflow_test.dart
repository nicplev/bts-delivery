import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/delivery.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/pre_delivery_checklist_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/repositories/deliveries_repository.dart';
import 'package:bts_delivery_app/screens/main/deliveries_screen.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:bts_delivery_app/widgets/deliveries_calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

void main() {
  testWidgets('opens today for assigned schools and starts school work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final repository = _DeliveriesRepository(today);

    await tester.pumpWidget(
      _app(
        repository,
        loadStaff: () => Stream.value(_staff(today)),
        textScale: 1.7,
        connectivity: ConnectivityStatus.offline,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_longName), findsOneWidget);
    expect(find.text('Scheduled delivery'), findsOneWidget);
    expect(find.text('School'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Checklist complete'), findsOneWidget);
    expect(find.byType(TableCalendar<Delivery>), findsNothing);
    expect(find.byTooltip('Add delivery'), findsNothing);
    final query = repository.queries.single;
    expect(query.start, today);
    expect(query.end, DateTime(today.year, today.month, today.day + 1));
    expect(query.schools, ['school']);

    await tester.ensureVisible(find.text('Open school'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open school'));
    await tester.pumpAndSettle();
    expect(find.text('School records'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(find.text(_longName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar fits the production theme at 320 px with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateTime.now();
    final repository = _DeliveriesRepository(today);
    await tester.pumpWidget(
      _app(repository,
          loadStaff: () => Stream.value(_staff(today)), textScale: 1.8),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(TableCalendar<Delivery>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin can add deliveries and calendar loads the page date range',
      (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final repository = _DeliveriesRepository(today);

    await tester.pumpWidget(
      _app(repository,
          isAdmin: true,
          loadStaff: () => Stream.error(StateError('lookup failed'))),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add delivery'), findsOneWidget);
    expect(find.text(_longName), findsOneWidget);
    expect(repository.queries.single.schools, isNull);

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(
      repository.queries.last,
      (
        start: DateTime(today.year, today.month),
        end: DateTime(today.year, today.month + 1),
        schools: null,
      ),
    );

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(
      repository.queries.last,
      (
        start: DateTime(today.year, today.month + 1),
        end: DateTime(today.year, today.month + 2),
        schools: null,
      ),
    );
    final calendar = tester.widget<TableCalendar<Delivery>>(
      find.byType(TableCalendar<Delivery>),
    );
    final selectedDay = DateTime.utc(today.year, today.month + 1, 15);
    calendar.onDaySelected!(selectedDay, selectedDay);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    final restored = tester.widget<TableCalendar<Delivery>>(
      find.byType(TableCalendar<Delivery>),
    );
    expect(restored.selectedDayPredicate!(selectedDay), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'shows a staff lookup error, retries, and waits for a linked account', (
    tester,
  ) async {
    final today = DateTime.now();
    final repository = _DeliveriesRepository(today);
    var attempts = 0;

    await tester.pumpWidget(
      _app(
        repository,
        loadStaff: () {
          attempts++;
          return attempts == 1
              ? Stream.error(StateError('lookup failed'))
              : Stream.value(null);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load your staff account'), findsOneWidget);
    expect(repository.queries, isEmpty);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Link your staff account'), findsOneWidget);
    expect(repository.queries, isEmpty);
  });

  testWidgets('manager scope stays selected when switching to the calendar',
      (tester) async {
    final today = DateTime.now();
    final repository = _DeliveriesRepository(today);
    await tester.pumpWidget(
      _app(
        repository,
        loadStaff: () => Stream.value(_staff(today).copyWith(role: 'manager')),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.queries.single.schools, ['school']);

    await tester.tap(find.byTooltip('Filter deliveries (my schools)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show All Deliveries'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.schools, isNull);

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.schools, isNull);
    expect(find.byTooltip('Filter deliveries (all schools)'), findsOneWidget);
  });

  test(
      'visible dates use exclusive local day boundaries across a year rollover',
      () {
    final firstDay = DateTime(2024, 12, 22);
    final focus = DateTime.utc(2025, 1, 2);

    final month = visibleDeliveryDates(
      firstDay: firstDay,
      focusedDay: focus,
      format: CalendarFormat.month,
    );
    expect(month, (start: DateTime(2025), end: DateTime(2025, 2)));
    expect(includesDeliveryDate(month, DateTime.utc(2025, 2)), isFalse);

    final week = visibleDeliveryDates(
      firstDay: firstDay,
      focusedDay: focus,
      format: CalendarFormat.week,
    );
    expect(week, (start: DateTime(2024, 12, 29), end: DateTime(2025, 1, 5)));

    final twoWeeks = visibleDeliveryDates(
      firstDay: firstDay,
      focusedDay: focus,
      format: CalendarFormat.twoWeeks,
    );
    expect(twoWeeks, (start: firstDay, end: DateTime(2025, 1, 5)));
  });
}

const _longName =
    'Springfield North Regional School and Early Learning Centre Campus';

Staff _staff(DateTime today) => Staff(
      id: 'staff',
      name: 'Driver',
      assignedSchoolIds: ['school'],
      createdAt: today,
    );

Widget _app(
  _DeliveriesRepository repository, {
  required Stream<Staff?> Function() loadStaff,
  bool isAdmin = false,
  double textScale = 1,
  ConnectivityStatus connectivity = ConnectivityStatus.online,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const DeliveriesScreen()),
      GoRoute(
        path: '/deliveries/:deliveryId/schools/:id',
        builder: (_, __) => const Scaffold(body: Text('School records')),
      ),
    ],
  );
  addTearDown(router.dispose);

  return ProviderScope(
    overrides: [
      deliveriesRepositoryProvider.overrideWithValue(repository),
      isAdminProvider.overrideWithValue(isAdmin),
      currentStaffProvider.overrideWith((_) => loadStaff()),
      connectivityStatusProvider
          .overrideWith((_) => Stream.value(connectivity)),
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
      deliveryChecklistStatusProvider.overrideWith(
        (_, __) => const AsyncValue.data(true),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

class _DeliveriesRepository implements DeliveriesRepository {
  _DeliveriesRepository(this.today);

  final DateTime today;
  final queries = <({DateTime start, DateTime end, List<String>? schools})>[];

  @override
  Stream<List<Delivery>> watchDeliveriesByDateRange(
    DateTime start,
    DateTime end, {
    List<String>? schoolIds,
  }) {
    queries.add((start: start, end: end, schools: schoolIds));
    if (today.isBefore(start) || !today.isBefore(end)) {
      return Stream.value(const []);
    }
    return Stream.value([
      Delivery(
        id: 'delivery',
        schoolId: 'school',
        schoolName: _longName,
        date: today,
        time: today.add(const Duration(hours: 8)),
        createdAt: today,
        vehicleCount: 2,
        palletCount: 5,
        notes: 'Use Gate 3 near the sports centre.',
      ),
    ]);
  }

  @override
  Future<Result<List<Staff>>> getAllStaff() async => const Result.success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
