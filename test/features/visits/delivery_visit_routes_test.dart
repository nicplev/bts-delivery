import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bts_delivery_app/app/router/app_router.dart';
import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/checklist_item.dart';
import 'package:bts_delivery_app/models/delivery.dart';
import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/offline/evidence_upload.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/school_timer.dart';
import 'package:bts_delivery_app/models/signoff_snapshot.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/checklist_providers.dart';
import 'package:bts_delivery_app/providers/deliveries_providers.dart';
import 'package:bts_delivery_app/providers/delivery_visit_provider.dart';
import 'package:bts_delivery_app/providers/field_draft_providers.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/offline_media_providers.dart';
import 'package:bts_delivery_app/providers/saved_edit_providers.dart';
import 'package:bts_delivery_app/providers/pre_delivery_checklist_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/repositories/auth_repository.dart';
import 'package:bts_delivery_app/repositories/classroom_edit.dart';
import 'package:bts_delivery_app/repositories/schools_repository.dart';
import 'package:bts_delivery_app/services/delivery_visit_access.dart';
import 'package:bts_delivery_app/screens/forms/classroom_detail_screen.dart';
import 'package:bts_delivery_app/screens/main/school_hub_screen.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/offline/field_draft_store.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:bts_delivery_app/widgets/delivery_visit_gate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:signature/signature.dart';

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
    final drafts = _FieldDrafts();
    final first = _VisitSchools();
    final second = _VisitSchools();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_FieldUser())),
        currentStaffProvider.overrideWith((_) => Stream.value(_staff)),
        todayDeliveriesProvider.overrideWith((_) => Stream.value([
              for (final id in ['first', 'second'])
                Delivery(
                  id: id,
                  schoolId: 'school',
                  schoolName: 'School',
                  date: DateTime(2025),
                  createdAt: DateTime(2025),
                ),
            ])),
        deliveryChecklistStatusProvider.overrideWith(
          (_, __) => const AsyncValue.data(false),
        ),
        authRepositoryProvider.overrideWithValue(_VisitAuth()),
        fieldDraftStoreProvider.overrideWith((_) async => drafts),
        savedEditsProvider.overrideWith((_) => Stream.value(const [])),
        offlineMediaOwnerProvider.overrideWith((_, __) => null),
        connectivityServiceProvider
            .overrideWithValue(_VisitOfflineConnectivity()),
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
      router.go('/home');
      await tester.pumpAndSettle();
      // The next visit opens from its card; later visits are rows.
      final openSchool = visit.deliveryId == 'first'
          ? find.widgetWithText(FilledButton, 'Open visit')
          : find.byKey(ValueKey(visit.deliveryId));
      await tester.ensureVisible(openSchool);
      await tester.pumpAndSettle();
      await tester.tap(openSchool);
      await tester.pumpAndSettle();
      expect(
          find.text('Classroom records ready on this device'), findsOneWidget);
      // Records list classrooms across year levels directly.
      expect(find.text('Year 1 · 0 of 10 packs'), findsOneWidget);
      await tester.ensureVisible(find.text('Room A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Room A'));
      await tester.pumpAndSettle();
      final room = tester.widget<ClassroomDetailScreen>(
        find.byType(ClassroomDetailScreen),
      );
      expect(room.deliveryId, visit.deliveryId);
      expect(find.text('10 packs expected'), findsOneWidget);
      expect(find.text('Unrecorded'), findsOneWidget);
    }

    await openRoom(
        const DeliveryVisit(deliveryId: 'first', schoolId: 'school'));
    await tester.tap(find.text('Incomplete'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '7');
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    final savedDraft = drafts.entries.values.single;
    expect(savedDraft.values['quantity'], '7');

    await tester.tap(find.text('Incomplete'));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    await tester.tap(find.text('Save packs'));
    await tester.pumpAndSettle();
    expect(first.room.completionStatus, ClassroomCompletionStatus.incomplete);
    expect(first.room.actualPacksDelivered, 7);
    expect(first.lastEditId, savedDraft.revision);
    expect(drafts.entries, isEmpty);
    expect(second.room.actualPacksDelivered, isNull);

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
    expect(find.text('Room A'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'capture retains handwriting and name and rechecks the visit review',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const schoolName = 'Example Primary School and Early Learning Centre';
    const savedAddress = '42 Example Street, Melbourne';
    const noteText = 'Check with the office before leaving the student packs.';
    final school = _VisitSchools(
      schoolName: schoolName,
      schoolAddress: savedAddress,
      notes: [Note(id: 'note', content: noteText, createdAt: DateTime(2025))],
    );
    addTearDown(school.dispose);
    final membership = StateProvider((_) => _staff);
    const emptyQueue = EvidenceUploadStatus(
      items: [],
      activeId: null,
      legacyReviewCount: 0,
      localError: false,
    );
    final queue = StateProvider((_) => emptyQueue);
    final worker = _VisitEvidenceWorker();
    final checklistItem = ChecklistItem(
      id: 'checked-packs',
      title: 'Packs checked',
      order: 0,
      createdAt: DateTime.utc(2025),
    );
    final checklist = StateProvider((_) => [checklistItem]);
    final container = ProviderContainer(
      overrides: [
        currentStaffProvider.overrideWith(
          (ref) => Stream.value(ref.watch(membership)),
        ),
        authStateProvider.overrideWith((_) => Stream.value(_FieldUser())),
        authRepositoryProvider.overrideWithValue(_VisitAuth()),
        deliveryTodayProvider.overrideWith((_) => DateTime(2025)),
        todayDeliveriesProvider.overrideWith((_) => Stream.value([
              Delivery(
                id: 'first',
                schoolId: 'school',
                schoolName: schoolName,
                date: DateTime(2025),
                createdAt: DateTime(2025),
              ),
            ])),
        deliveryChecklistStatusProvider.overrideWith(
          (_, __) => const AsyncValue.data(false),
        ),
        savedEditsProvider.overrideWith((_) => Stream.value(const [])),
        deliveryVisitReadinessProvider.overrideWith(
          (_, __) async => (
            uid: 'field-owner',
            status: DeliveryVisitReadiness.ready,
          ),
        ),
        activeChecklistItemsProvider.overrideWith(
          (ref) => Stream.value(ref.watch(checklist)),
        ),
        baseSchoolsRepositoryProvider.overrideWithValue(school),
        visitSchoolsRepositoryFactoryProvider.overrideWithValue((_) => school),
        offlineMediaOwnerProvider.overrideWith((_, __) => null),
        connectivityServiceProvider
            .overrideWithValue(_VisitOfflineConnectivity()),
        connectivityStatusProvider.overrideWith(
          (_) => Stream.value(ConnectivityStatus.offline),
        ),
        evidenceUploadWorkerProvider.overrideWith((_) async => worker),
        evidenceUploadsProvider.overrideWith(
          (ref) => Stream.value(ref.watch(queue)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(evidenceUploadWorkerProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: container.read(appRouterProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final open = find.text('Open visit');
    await tester.dragUntilVisible(
      open,
      find.byType(CustomScrollView).first,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(SchoolHubScreen), findsOneWidget);

    Future<void> scrollVisitTo(Finder target, {double delta = -160}) async {
      final visible = target.hitTestable();
      for (var attempt = 0;
          attempt < 18 && visible.evaluate().isEmpty;
          attempt++) {
        final viewport = tester.getRect(find.byType(NestedScrollView));
        await tester.dragFrom(
          Offset(viewport.left + 24, viewport.center.dy),
          Offset(0, delta),
        );
        await tester.pumpAndSettle();
      }
      expect(visible, findsOneWidget);
    }

    expect(find.text('Classroom records ready on this device'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Room A'),
      find.byType(NestedScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.text('Room A').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The section switch stays pinned while the records scroll.
    expect(find.text('Sign-off').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Sign-off'));
    await tester.pumpAndSettle();
    expect(find.text('of 10 packs recorded'), findsOneWidget);
    expect(find.text('10 packs outstanding in 1 classroom'), findsOneWidget);
    expect(find.text('Room A'), findsOneWidget);
    final allClassrooms = find.text('No classrooms complete yet');
    await scrollVisitTo(allClassrooms);
    await tester.tap(allClassrooms);
    await tester.pumpAndSettle();
    expect(find.text('10 expected packs'), findsOneWidget);
    final viewNotes = find.text('View notes');
    await scrollVisitTo(viewNotes);
    await tester.tap(viewNotes);
    await tester.pumpAndSettle();
    expect(find.text(noteText).hitTestable(), findsOneWidget);

    final capture = find.text('Continue to signature');
    final back = find.byTooltip('Back to review');
    Future<void> openCapture() async {
      // At large text the action follows the review content.
      await scrollVisitTo(capture, delta: -320);
      await tester.tap(capture.hitTestable());
      await tester.pumpAndSettle();
      expect(back, findsOneWidget);
      expect(find.byType(AppGlassTabBar), findsNothing);
    }

    await openCapture();
    // The subtitle names the school and date, never an internal id.
    expect(find.textContaining('Visit first'), findsNothing);
    expect(find.textContaining('$schoolName · '), findsOneWidget);
    Future<void> scrollCaptureTo(Finder target) async {
      final scroll = find.byType(SingleChildScrollView);
      for (var attempt = 0;
          attempt < 18 && target.hitTestable().evaluate().isEmpty;
          attempt++) {
        final viewport = tester.getRect(scroll);
        await tester.dragFrom(
          Offset(viewport.left + 12, viewport.center.dy),
          const Offset(0, -130),
        );
        await tester.pumpAndSettle();
      }
      expect(target.hitTestable(), findsOneWidget);
    }

    final signerName = find.byType(TextField);
    await scrollCaptureTo(signerName);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      final nameSemantics = tester.getSemantics(signerName).getSemanticsData();
      expect(nameSemantics.label, contains('Receiver name'));
      expect(nameSemantics.label, isNot(contains('Signature')));
    } finally {
      semantics.dispose();
    }
    await tester.tap(signerName.hitTestable());
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(signerName.hitTestable(), findsOneWidget);
    await tester.enterText(signerName, 'Example Visitor');
    await tester.pumpAndSettle();

    final review = find.text('Review and save');
    await scrollCaptureTo(review);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.text('Example Visitor'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();

    await scrollCaptureTo(review);
    await tester.tap(review.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Please provide your signature').hitTestable(),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final canvas = find.byType(Signature);
    await scrollCaptureTo(canvas);
    await tester.dragFrom(
        tester.getCenter(canvas) - const Offset(26, 8), const Offset(53, 19));
    await tester.pumpAndSettle();
    final signature = tester.widget<Signature>(canvas).controller;
    expect(signature.points, isNotEmpty);
    final points = [...signature.points];

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byType(Signature), findsNothing);
    await openCapture();
    expect(tester.widget<TextField>(signerName).controller?.text,
        'Example Visitor');
    expect(tester.widget<Signature>(canvas).controller.points, points);

    container.read(checklist.notifier).state = [
      for (var index = 0;
          index <= SignOffSnapshot.maxReviewChecklistItems;
          index++)
        checklistItem.copyWith(id: 'item-$index'),
    ];
    await tester.pumpAndSettle();
    await scrollCaptureTo(review);
    await tester.tap(review.hitTestable());
    await tester.pumpAndSettle();
    expect(find.textContaining('The signing checklist exceeds 500 items'),
        findsOneWidget);
    expect(find.text('Review delivery details'), findsNothing);
    expect(worker.saved, isEmpty);
    expect(tester.widget<Signature>(canvas).controller.points, points);
    container.read(checklist.notifier).state = [checklistItem];
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    Future<void> confirmReview() async {
      final checkbox =
          find.widgetWithText(CheckboxListTile, checklistItem.title);
      await tester.ensureVisible(checkbox);
      await tester.pump();
      await tester.tap(checkbox);
      await tester.pump();
      await tester.tap(find.text('Save for review'));
    }

    await scrollCaptureTo(review);
    await tester.tap(review.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Review delivery details'), findsOneWidget);
    expect(find.textContaining('cached or unavailable'), findsOneWidget);
    school.reviewChanged = true;
    await confirmReview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        find.text('Delivery information changed. Review the updated details.'),
        findsOneWidget);
    expect(find.text('Use the west entrance.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widget<Signature>(canvas).controller.points, points);

    await scrollCaptureTo(review);
    await tester.tap(review.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await confirmReview();
    // The actual signature encoder rasterizes through the engine. Pump Dart
    // work and allow its raster callback to complete outside the test clock.
    for (var attempt = 0; attempt < 80 && worker.saved.isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 20),
          ));
    }
    await tester.pumpAndSettle();
    expect(worker.saved, hasLength(1));
    final saved = worker.saved.single;
    expect(saved.ownerUid, 'field-owner');
    expect(saved.schoolId, 'school');
    expect(saved.deliveryId, 'first');
    final expectedPayload = jsonDecode(
      File('test/fixtures/visit_signature_payload.json').readAsStringSync(),
    );
    expect(saved.payload, expectedPayload);
    expect(saved.bytes.take(4), [0x89, 0x50, 0x4e, 0x47]);
    expect(find.byType(Signature), findsNothing);
    expect(find.text('Signature saved on this device'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    EvidenceUploadStatus pendingFor(String visitId) => EvidenceUploadStatus(
          items: [
            EvidenceUpload(
              id: 'saved',
              kind: EvidenceKind.signature,
              ownerUid: 'field-owner',
              schoolId: 'school',
              deliveryId: visitId,
              localFileName: 'pending_evidence/saved.png',
              storagePath: 'schools/school/signoffs/saved.png',
              createdAt: DateTime(2025),
            ),
          ],
          activeId: 'saved',
          legacyReviewCount: 0,
          localError: false,
        );
    container.read(queue.notifier).state = pendingFor('second');
    await tester.pumpAndSettle();
    expect(capture, findsOneWidget);
    container.read(queue.notifier).state = pendingFor('first');
    await tester.pumpAndSettle();
    expect(find.text('Signature saved on this device'), findsOneWidget);
    expect(capture, findsNothing);
    container.read(queue.notifier).state = emptyQueue;
    await tester.pumpAndSettle();

    expect(find.text('Info').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    await scrollVisitTo(find.text('School information'));
    await scrollVisitTo(find.text('Open in Maps'));
    final infoPage = find.byKey(const PageStorageKey('school-info'));
    expect(
      find.descendant(of: infoPage, matching: find.text(savedAddress)),
      findsOneWidget,
    );
    expect(find.byType(GoogleMap), findsNothing);
    expect(tester.takeException(), isNull);

    expect(find.text('Records').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Records'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Room A'),
      find.byType(NestedScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.text('Room A').hitTestable(), findsOneWidget);
    expect(find.text('Sign-off').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Sign-off'));
    await tester.pumpAndSettle();
    await openCapture();
    container.read(membership.notifier).state =
        _staff.copyWith(assignedSchoolIds: const []);
    await tester.pumpAndSettle();
    expect(back, findsNothing);
    expect(find.text('Example Visitor'), findsNothing);
    expect(find.byType(Signature), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
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

class _VisitAuth implements AuthRepository {
  @override
  User? get currentUser => _FieldUser();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FieldDrafts implements FieldDraftStore {
  final entries = <String, FieldDraft>{};

  @override
  Future<FieldDraft?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, FieldDraft draft) async =>
      entries[key] = draft;

  @override
  Future<void> remove(String key, {required String revision}) async {
    if (entries[key]?.revision == revision) entries.remove(key);
  }
}

class _VisitSchools implements SchoolsRepository {
  _VisitSchools({
    this.schoolName = 'School',
    this.schoolAddress,
    this.notes = const [],
  });

  final String schoolName;
  final String? schoolAddress;
  final List<Note> notes;
  bool reviewChanged = false;
  final _classroomChanges = StreamController<List<Classroom>>.broadcast();
  String? lastEditId;
  Classroom room =
      Classroom(id: 'room', name: 'Room A', createdAt: DateTime(2025));

  @override
  Stream<List<School>> watchSchools({List<String>? schoolIds}) => Stream.value([
        School(
          id: 'school',
          name: schoolName,
          address: schoolAddress,
          createdAt: DateTime(2025),
        ),
      ]);

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
      Stream.value(notes);

  @override
  Stream<SignOff?> watchSignOff(String schoolId) => Stream.value(null);

  @override
  Future<SignOffSnapshot> readSignOffDraft(
    String schoolId, {
    required bool server,
    String? deliveryId,
  }) async {
    final empty = SignOffSnapshot.incomplete(schoolId);
    return SignOffSnapshot(
      sourceReadAt: DateTime.utc(2025),
      serverReviewed: server,
      summary: {
        ...empty.summary,
        'totalPacks': 10,
        'notes':
            reviewChanged ? 'Use the west entrance.' : 'Use the main entrance.',
      },
    );
  }

  @override
  Stream<SignedEvidence?> watchSignedEvidence(
    String schoolId,
    String? deliveryId,
  ) =>
      Stream.value(null);

  @override
  Stream<List<Contact>> watchContacts(String schoolId) =>
      Stream.value(const []);

  @override
  Stream<List<SchoolTimer>> watchTimerHistory(String schoolId,
          {int limit = 20}) =>
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
    String? editId,
  }) async {
    lastEditId = editId;
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

class _VisitEvidenceWorker implements EvidenceUploadWorker {
  final saved = <({
    String ownerUid,
    String schoolId,
    String? deliveryId,
    Uint8List bytes,
    Map<String, dynamic> payload,
  })>[];

  @override
  Future<void> enqueueSignature({
    required String id,
    required String ownerUid,
    required String schoolId,
    String? deliveryId,
    required Uint8List bytes,
    required Map<String, dynamic> payload,
  }) async {
    saved.add((
      ownerUid: ownerUid,
      schoolId: schoolId,
      deliveryId: deliveryId,
      bytes: bytes,
      payload: payload,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VisitOfflineConnectivity implements ConnectivityService {
  @override
  ConnectivityStatus get currentStatus => ConnectivityStatus.offline;

  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();

  @override
  Future<void> checkConnectivity() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
