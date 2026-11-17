import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/school_timer.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/delivery_visit_provider.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/offline_media_providers.dart';
import 'package:bts_delivery_app/providers/school_timer_providers.dart';
import 'package:bts_delivery_app/providers/schools_providers.dart';
import 'package:bts_delivery_app/screens/forms/classrooms_screen.dart';
import 'package:bts_delivery_app/screens/main/school_hub_screen.dart';
import 'package:bts_delivery_app/services/delivery_visit_access.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:bts_delivery_app/widgets/records_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _visit = DeliveryVisit(deliveryId: 'delivery', schoolId: 'school');
final _created = DateTime(2026);

final _levels = [
  YearLevel(id: 'y1', label: 'Year 1', createdAt: _created),
  YearLevel(id: 'sp', label: 'Specialist', createdAt: _created),
  YearLevel(id: 'p', label: 'Prep', createdAt: _created),
];

final _rooms = <String, List<Classroom>>{
  'p': [
    Classroom(
      id: 'prep-a',
      name: 'Prep A',
      createdAt: _created,
      completionStatus: ClassroomCompletionStatus.complete,
    ),
  ],
  'y1': [
    Classroom(
      id: 'room-1a',
      name: 'Room 1A',
      createdAt: _created,
      completionStatus: ClassroomCompletionStatus.incomplete,
      actualPacksDelivered: 13,
    ),
    Classroom(id: 'room-1b', name: 'Room 1B', createdAt: _created),
  ],
  'sp': const [],
};

const _packs = {'prep-a': 20, 'room-1a': 24, 'room-1b': 12};

List<Override> _overrides({
  bool visit = true,
  bool canEdit = true,
  bool canControlTimer = false,
}) =>
    [
      if (visit) activeDeliveryVisitProvider.overrideWithValue(_visit),
      canEditSchoolDataProvider.overrideWithValue(canEdit),
      isAdminProvider.overrideWithValue(false),
      canControlTimerProvider.overrideWithValue(canControlTimer),
      schoolByIdProvider.overrideWith((_, id) => Stream.value(
          School(id: id, name: 'Oakfield Primary', createdAt: _created))),
      yearLevelsProvider.overrideWith((_, __) => Stream.value(_levels)),
      classroomsProvider
          .overrideWith((_, p) => Stream.value(_rooms[p.yearLevelId]!)),
      packTotalProvider.overrideWith((_, p) => Stream.value(PackTotal(
          id: 'pack', total: _packs[p.classroomId]!, createdAt: _created))),
      yearLevelBreakdownsProvider.overrideWith((_, __) => Stream.value([])),
      yearLevelConsumablesTotalsProvider.overrideWith((_, __) async => {}),
      activeSchoolTimerProvider
          .overrideWith((_, __) => Stream<SchoolTimer?>.value(null)),
      schoolTimerHistoryProvider.overrideWith((_, __) => Stream.value([])),
      contactsProvider.overrideWith((_, __) => Stream.value([])),
      offlineMediaOwnerProvider.overrideWith((_, __) => null),
      connectivityStatusProvider
          .overrideWith((_) => Stream.value(ConnectivityStatus.online)),
      evidenceUploadsProvider.overrideWith((_) => Stream.value(
            const EvidenceUploadStatus(
              items: [],
              activeId: null,
              legacyReviewCount: 0,
              localError: false,
            ),
          )),
      deliveryVisitReadinessProvider.overrideWith((_, __) async =>
          (uid: 'staff', status: DeliveryVisitReadiness.ready)),
    ];

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.lightTheme, home: home),
    );

void main() {
  testWidgets('records summary, year order and the year filter', (
    tester,
  ) async {
    await tester.pumpWidget(_app(
      const Scaffold(body: RecordsTab(schoolId: 'school')),
      _overrides(),
    ));
    await tester.pumpAndSettle();

    // 20 (Prep A complete) + 13 (Room 1A partial) of 20 + 24 + 12.
    expect(find.text('33 of 56 packs recorded'), findsOneWidget);
    expect(find.text('Prep · 20 of 20 packs'), findsOneWidget);
    expect(find.text('Year 1 · 13 of 24 packs'), findsOneWidget);
    expect(find.text('Year 1 · 0 of 12 packs'), findsOneWidget);
    expect(find.text('No classrooms yet'), findsOneWidget);
    // Prep, Year 1, then the non-standard level.
    final prep = tester.getTopLeft(find.text('Prep A')).dy;
    final room = tester.getTopLeft(find.text('Room 1A')).dy;
    final specialist = tester.getTopLeft(find.text('Specialist')).dy;
    expect(prep, lessThan(room));
    expect(room, lessThan(specialist));
    expect(find.text('Timer'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('year-filter-year1')));
    await tester.pumpAndSettle();
    expect(find.text('Prep A'), findsNothing);
    expect(find.text('Room 1A'), findsOneWidget);
    expect(find.text('Room 1B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('year-filter-year1')));
    await tester.pumpAndSettle();
    expect(find.text('Prep A'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('year-filter-level-sp')));
    await tester.pumpAndSettle();
    expect(find.text('Room 1A'), findsNothing);
    expect(find.text('No classrooms yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('template records show expected packs without a timer', (
    tester,
  ) async {
    await tester.pumpWidget(_app(
      const Scaffold(body: RecordsTab(schoolId: 'school')),
      _overrides(visit: false),
    ));
    await tester.pumpAndSettle();
    expect(find.text('56 expected packs'), findsOneWidget);
    expect(find.text('Year 1 · 24 expected packs'), findsOneWidget);
    expect(find.text('Timer'), findsNothing);
  });

  testWidgets('timer row offers start to staff who control timers', (
    tester,
  ) async {
    await tester.pumpWidget(_app(
      const Scaffold(body: RecordsTab(schoolId: 'school')),
      _overrides(canControlTimer: true),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visit-timer-control')), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('00:00:00'), findsOneWidget);
  });

  testWidgets('records render in high-contrast dark', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        theme: AppTheme.highContrastDarkTheme,
        home: const Scaffold(body: RecordsTab(schoolId: 'school')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('33 of 56 packs recorded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hub remembers the year filter across tabs', (tester) async {
    await tester.pumpWidget(_app(
      const SchoolHubScreen(schoolId: 'school', deliveryId: 'delivery'),
      _overrides(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Delivery visit'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('year-filter-year1')));
    await tester.pumpAndSettle();
    expect(find.text('Prep A'), findsNothing);

    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('School information'), findsOneWidget);
    await tester.tap(find.text('Records'));
    await tester.pumpAndSettle();
    expect(find.text('Room 1A'), findsOneWidget);
    expect(find.text('Prep A'), findsNothing);
  });

  testWidgets(
      'hub fits 320 pt at 200 % text and keeps structure editing reachable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_app(
      SchoolHubScreen(
        schoolId: 'school',
        deliveryId: 'delivery',
        visitDate: DateTime(2026, 11, 17),
      ),
      _overrides(canControlTimer: true),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Oakfield Primary'), findsOneWidget);
    expect(find.text('Tue 17 Nov 2026 · Delivery visit'), findsOneWidget);
    expect(find.text('Classroom records ready on this device'), findsOneWidget);

    // The last row scrolls into view without overflow.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('records-manage-classrooms')),
      find.byType(NestedScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('hub-tab-2')),
      find.byType(NestedScrollView),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hub-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('School information'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('hub-options')));
    await tester.pumpAndSettle();
    expect(find.text('Visit options'), findsOneWidget);
    expect(find.text('Add year level'), findsOneWidget);
    final manage = find.byKey(const ValueKey('hub-option-manage-classrooms'));
    await tester.ensureVisible(manage);
    await tester.pumpAndSettle();
    await tester.tap(manage);
    await tester.pumpAndSettle();
    // At 200 % the rows sit below the sheet's introduction: scroll to them.
    final prepRow =
        find.byKey(const ValueKey('year-level-p'), skipOffstage: false);
    await tester.ensureVisible(prepRow);
    await tester.pumpAndSettle();
    expect(prepRow.hitTestable(), findsOneWidget);
    expect(find.text('2 classrooms', skipOffstage: false), findsOneWidget);
    final add = find.byKey(const ValueKey('manage-add-year-level'));
    await tester.dragUntilVisible(
      add,
      find
          .descendant(
            of: find.byType(AppGlassSheetFrame),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(add.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('classrooms screen floats "Add classroom" and keeps the dialog',
      (tester) async {
    await tester.pumpWidget(_app(
      const ClassroomsScreen(schoolId: 'school', yearLevelId: 'y1'),
      _overrides(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Year 1'), findsOneWidget);
    expect(find.text('0 of 2 classrooms complete'), findsOneWidget);
    expect(find.text('Room 1A'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-classroom')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Add classroom'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a name'), findsOneWidget);
  });
}
