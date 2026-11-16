import 'dart:async';

import 'package:bts_delivery_app/app/router/app_router.dart';
import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/school_timer.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/deliveries_providers.dart';
import 'package:bts_delivery_app/providers/delivery_visit_provider.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/repositories/classroom_edit.dart';
import 'package:bts_delivery_app/repositories/schools_repository.dart';
import 'package:bts_delivery_app/services/delivery_visit_access.dart';
import 'package:bts_delivery_app/screens/forms/classroom_detail_screen.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:bts_delivery_app/widgets/delivery_visit_gate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stale visit readiness cannot bypass connectivity or assignment',
      (
    tester,
  ) async {
    const visit = DeliveryVisit(deliveryId: 'first', schoolId: 'school');
    final online = StateProvider((_) => true);
    final memberships = StreamController<Staff?>();
    final offlineCheck = Completer<VisitReadiness>();
    var prepared = false;
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FieldUser())),
        currentStaffProvider.overrideWith((_) => memberships.stream),
        isOnlineProvider.overrideWith((ref) => ref.watch(online)),
        deliveryVisitReadinessProvider.overrideWith((ref, _) async {
          if (!ref.watch(isOnlineProvider)) return offlineCheck.future;
          return (
            uid: 'field-owner',
            status: prepared
                ? DeliveryVisitReadiness.ready
                : DeliveryVisitReadiness.onlineOnly,
          );
        }),
      ],
    );
    addTearDown(memberships.close);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: DeliveryVisitGate(
            visit: visit,
            child: Text('Classroom workspace'),
          ),
        ),
      ),
    );
    memberships.add(_staff);
    await tester.pumpAndSettle();
    expect(find.text('Classroom workspace'), findsOneWidget);

    container.read(online.notifier).state = false;
    await tester.pumpAndSettle();
    final loading = container.read(deliveryVisitReadinessProvider(visit));
    expect(loading.isLoading, isTrue);
    expect(loading.valueOrNull?.status, DeliveryVisitReadiness.onlineOnly);
    expect(find.text('Classroom workspace'), findsNothing);
    expect(find.text('Checking saved visit records'), findsOneWidget);

    offlineCheck.complete((
      uid: 'field-owner',
      status: DeliveryVisitReadiness.unavailableOffline,
    ));
    await tester.pumpAndSettle();
    expect(find.text('This visit isn’t available offline yet'), findsOneWidget);

    prepared = true;
    container.read(online.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.text('Classroom workspace'), findsOneWidget);

    memberships.add(_staff.copyWith(assignedSchoolIds: []));
    await tester.pumpAndSettle();
    expect(find.text('Classroom workspace'), findsNothing);
  });

  testWidgets('nested classroom routes isolate two visits to the same school', (
    tester,
  ) async {
    final first = _VisitSchools();
    final second = _VisitSchools();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FieldUser())),
        currentStaffProvider.overrideWith((_) => Stream.value(_staff)),
        todayDeliveriesProvider.overrideWith((_) => Stream.value(const [])),
        connectivityStatusProvider.overrideWith(
          (_) => Stream.value(ConnectivityStatus.offline),
        ),
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
        visitSchoolsRepositoryFactoryProvider.overrideWithValue(
          (visit) => switch (visit.deliveryId) {
            'first' => first,
            'second' => second,
            _ => throw StateError('Unprepared visit opened a repository'),
          },
        ),
        deliveryVisitReadinessProvider.overrideWith(
          (_, visit) async => (
            uid: 'field-owner',
            status: visit.deliveryId == 'uncached'
                ? DeliveryVisitReadiness.unavailableOffline
                : DeliveryVisitReadiness.ready,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openRoom(DeliveryVisit visit) async {
      router.go(schoolWorkPath(visit.schoolId, visit: visit));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Year 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Room A'));
      await tester.pumpAndSettle();
      final room = tester.widget<ClassroomDetailScreen>(
        find.byType(ClassroomDetailScreen),
      );
      expect(room.deliveryId, visit.deliveryId);
    }

    await openRoom(
        const DeliveryVisit(deliveryId: 'first', schoolId: 'school'));
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect(first.room.completionStatus, ClassroomCompletionStatus.complete);
    expect(second.room.completionStatus, ClassroomCompletionStatus.notAttended);
    expect(find.text('Classroom status saved'), findsOneWidget);

    await openRoom(
        const DeliveryVisit(deliveryId: 'second', schoolId: 'school'));
    expect(first.room.completionStatus, ClassroomCompletionStatus.complete);
    expect(second.room.completionStatus, ClassroomCompletionStatus.notAttended);

    router.go(schoolWorkPath(
      'school',
      visit: const DeliveryVisit(deliveryId: 'uncached', schoolId: 'school'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('This visit isn’t available offline yet'), findsOneWidget);
    expect(find.text('Year 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

final _staff = Staff(
  id: 'staff',
  uid: 'field-owner',
  name: 'Driver',
  assignedSchoolIds: const ['school'],
  createdAt: DateTime(2025),
);

class _FieldUser implements User {
  @override
  String get uid => 'field-owner';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VisitSchools implements SchoolsRepository {
  final _classroomChanges = StreamController<List<Classroom>>.broadcast();
  Classroom room =
      Classroom(id: 'room', name: 'Room A', createdAt: DateTime(2025));

  @override
  Stream<List<School>> watchSchools({List<String>? schoolIds}) => Stream.value(
      [School(id: 'school', name: 'School', createdAt: DateTime(2025))]);

  @override
  Stream<List<YearLevel>> watchYearLevels(String schoolId) => Stream.value(
      [YearLevel(id: 'level', label: 'Year 1', createdAt: DateTime(2025))]);

  @override
  Stream<List<Classroom>> watchClassrooms(
      String schoolId, String yearLevelId) async* {
    yield [room];
    yield* _classroomChanges.stream;
  }

  @override
  Stream<PackTotal?> watchLatestPackTotal(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value(PackTotal(id: 'pack', total: 10, createdAt: DateTime(2025)));

  @override
  Stream<List<Consumable>> watchClassroomConsumables(
    String schoolId,
    String yearLevelId,
    String classroomId,
  ) =>
      Stream.value(const []);

  @override
  Stream<List<YearLevelBreakdown>> watchYearLevelBreakdowns(
    String schoolId,
    String yearLevelId,
    String classroomId,
  ) =>
      Stream.value(const []);

  @override
  Stream<List<Note>> watchClassroomNotes(
    String schoolId,
    String yearLevelId,
    String classroomId,
  ) =>
      Stream.value(const []);

  @override
  Stream<List<Photo>> watchClassroomPhotos(
          String schoolId, String yearLevelId, String classroomId,
          {String? deliveryId}) =>
      Stream.value(const []);

  @override
  Stream<SchoolTimer?> watchActiveTimer(String schoolId) => Stream.value(null);

  @override
  Future<Result<ClassroomEditReceipt>> updateClassroomStatus(
    String schoolId,
    String yearLevelId,
    String classroomId, {
    required ClassroomCompletionStatus status,
    required int? actualPacksDelivered,
    required String updatedBy,
  }) async {
    room = room.copyWith(
      completionStatus: status,
      actualPacksDelivered: actualPacksDelivered,
      lastUpdatedBy: updatedBy,
      lastUpdatedAt: DateTime(2025),
    );
    _classroomChanges.add([room]);
    return Result.success((
      status: ClassroomEditStatus.saved,
      acknowledgment: Future.value(const Result.success(null)),
    ));
  }

  Future<void> dispose() => _classroomChanges.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
