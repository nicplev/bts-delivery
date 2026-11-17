import 'dart:async';

import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/offline/saved_edit.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/delivery_visit_provider.dart';
import 'package:bts_delivery_app/providers/field_draft_providers.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/offline_media_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/providers/saved_edit_providers.dart';
import 'package:bts_delivery_app/providers/schools_providers.dart';
import 'package:bts_delivery_app/repositories/auth_repository.dart';
import 'package:bts_delivery_app/repositories/classroom_edit.dart';
import 'package:bts_delivery_app/repositories/schools_repository.dart';
import 'package:bts_delivery_app/screens/forms/classroom_detail_screen.dart';
import 'package:bts_delivery_app/screens/forms/consumables_screen.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/offline/field_draft_store.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _visit = DeliveryVisit(deliveryId: 'monday', schoolId: 'school');

void main() {
  testWidgets('packs card shows progress; the sheet steps, fills and saves',
      (tester) async {
    final schools = _Schools(actual: 13);
    await _pumpRoom(tester, schools);

    expect(find.text('Room 1A'), findsOneWidget);
    expect(find.text('Year 1 · Oakfield Primary'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('of 24 recorded'), findsOneWidget);
    expect(find.text('11 packs still to deliver'), findsOneWidget);
    expect(find.byType(AppProgressBar), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(find.bySemanticsLabel('Classroom options'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('record-packs')));
    await tester.pumpAndSettle();
    expect(find.text('Year 1 · 24 packs expected'), findsOneWidget);
    expect(_field(tester).controller!.text, '13');

    await tester.tap(find.bySemanticsLabel('One more pack'));
    await tester.pump();
    expect(_field(tester).controller!.text, '14');
    expect(find.text('10 packs still to deliver'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('One fewer pack'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('One fewer pack'));
    await tester.pump();
    expect(_field(tester).controller!.text, '12');

    await tester.tap(find.text('All 24 delivered'));
    await tester.pump();
    expect(_field(tester).controller!.text, '24');
    expect(find.text('All packs delivered'), findsOneWidget);
    expect(
        find.text('Draft saved on this device').evaluate().isNotEmpty ||
            find.text('Saving draft…').evaluate().isNotEmpty,
        isTrue);

    await tester.tap(find.text('Save packs'));
    await tester.pumpAndSettle();
    expect(schools.room.completionStatus, ClassroomCompletionStatus.incomplete);
    expect(schools.room.actualPacksDelivered, 24);
    expect(schools.lastEditId, isNotNull);
    expect(find.text('Classroom status saved'), findsOneWidget);
    expect(find.text('Save packs'), findsNothing);
    expect(find.text('All packs delivered'), findsOneWidget);
  });

  testWidgets('typed packs keep the existing validation', (tester) async {
    final schools = _Schools(actual: null);
    await _pumpRoom(tester, schools);

    await tester.tap(find.byKey(const ValueKey('record-packs')));
    await tester.pumpAndSettle();
    expect(_field(tester).controller!.text, isEmpty);
    await tester.enterText(find.byType(TextFormField), 'twelve');
    await tester.tap(find.text('Save packs'));
    await tester.pumpAndSettle();
    expect(
        find.text('Enter a whole number from 0 to 1,000,000.'), findsOneWidget);
    expect(schools.lastEditId, isNull);

    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Save packs'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a quantity.'), findsOneWidget);
    expect(schools.lastEditId, isNull);
  });

  testWidgets(
      'unrecorded packs, offline capsule, saved-on-device line and '
      'admin pack total stay separate', (tester) async {
    final schools = _Schools(actual: null);
    await _pumpRoom(
      tester,
      schools,
      offline: true,
      admin: true,
      edits: [
        SavedEdit(
          EditIntent(
            id: '00000000-0000-4000-8000-000000000001',
            ownerUid: 'owner',
            schoolId: 'school',
            deliveryId: 'monday',
            yearLevelId: 'level',
            classroomId: 'room',
            kind: SavedEditKind.classroomStatus,
            capturedAt: DateTime.utc(2025),
            values: const {
              'completionStatus': 'incomplete',
              'actualPacksDelivered': 3,
            },
            updatedBy: 'Driver',
          ),
          SavedEditState.waiting,
        ),
      ],
    );

    expect(find.text('Unrecorded'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('24 packs expected'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(
        find.text('Saved on this device · uploads resume when you reconnect'),
        findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Classroom options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update pack total'));
    await tester.pumpAndSettle();
    expect(find.text('Number of packs'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets(
      '320 pt at 200 % text: no overflow and nothing ends under the '
      'floating action', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final schools = _Schools(
        actual: 13,
        consumables: [
          Consumable(
            id: 'tissues',
            itemName: 'Tissues',
            quantity: 12,
            unit: 'boxes',
            actualQuantityDelivered: 7,
            createdAt: DateTime(2025),
          ),
        ],
        photosFail: true);
    await _pumpRoom(tester, schools, textScale: 2, admin: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Could not load synced photos'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final lastRow = tester.getRect(find.text('No notes yet'));
    final action = tester.getRect(find.byKey(const ValueKey('record-packs')));
    expect(lastRow.bottom, lessThanOrEqualTo(action.top));

    await tester.tap(find.byKey(const ValueKey('record-packs')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Save packs'), findsOneWidget);
  });

  testWidgets('renders in dark and both high-contrast themes', (tester) async {
    for (final theme in [
      AppTheme.darkTheme,
      AppTheme.highContrastLightTheme,
      AppTheme.highContrastDarkTheme,
    ]) {
      await _pumpRoom(tester, _Schools(actual: 30),
          theme: theme, offline: true);
      expect(tester.takeException(), isNull);
      expect(find.text('6 packs more than expected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-packs')));
      await tester.pumpAndSettle();
      expect(find.text('6 packs more than expected'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('consumables screen floats one add action and lists items',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumablesProvider.overrideWith((ref, _) => Stream.value([
                Consumable(
                  id: 'paper',
                  itemName: 'Copy paper A4',
                  quantity: 6,
                  unit: 'reams',
                  createdAt: DateTime(2025),
                ),
              ])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ConsumablesScreen(schoolId: 'school'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Consumables'), findsOneWidget);
    expect(find.text('Copy paper A4'), findsOneWidget);
    expect(find.text('6 reams'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-consumable')));
    await tester.pumpAndSettle();
    expect(find.text('Add consumable'), findsWidgets);
    expect(find.text('Item name'), findsOneWidget);
  });
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

Future<void> _pumpRoom(
  WidgetTester tester,
  _Schools schools, {
  bool offline = false,
  bool admin = false,
  ThemeData? theme,
  double textScale = 1,
  List<SavedEdit> edits = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeDeliveryVisitProvider.overrideWithValue(_visit),
        schoolsRepositoryProvider.overrideWithValue(schools),
        baseSchoolsRepositoryProvider.overrideWithValue(schools),
        authStateProvider.overrideWith((_) => Stream.value(_User())),
        authRepositoryProvider.overrideWithValue(_Auth()),
        currentStaffProvider.overrideWith((_) => Stream.value(_staff)),
        isAdminProvider.overrideWithValue(admin),
        fieldDraftStoreProvider.overrideWith((_) async => _Drafts()),
        savedEditsProvider.overrideWith((_) => Stream.value(edits)),
        connectivityStatusProvider.overrideWith((_) => Stream.value(
            offline ? ConnectivityStatus.offline : ConnectivityStatus.online)),
        evidenceUploadWorkerProvider
            .overrideWith((_) => Completer<EvidenceUploadWorker>().future),
        evidenceUploadsProvider.overrideWith(
          (_) => Stream.value(const EvidenceUploadStatus(
            items: [],
            activeId: null,
            legacyReviewCount: 0,
            localError: false,
          )),
        ),
        offlineMediaOwnerProvider.overrideWith((_, __) => null),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, child) {
            // The app keeps the auth stream alive before a form opens.
            ref.watch(authStateProvider);
            return child!;
          },
          child: const ClassroomDetailScreen(
            schoolId: 'school',
            yearLevelId: 'level',
            classroomId: 'room',
            deliveryId: 'monday',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _staff = Staff(
  id: 'staff',
  uid: 'owner',
  name: 'Driver',
  assignedSchoolIds: const ['school'],
  createdAt: DateTime(2025),
);

class _User implements User {
  @override
  String get uid => 'owner';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthRepository {
  @override
  User? get currentUser => _User();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Drafts implements FieldDraftStore {
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

class _Schools implements SchoolsRepository {
  _Schools({
    required int? actual,
    this.consumables = const [],
    this.photosFail = false,
  }) : room = Classroom(
          id: 'room',
          name: 'Room 1A',
          actualPacksDelivered: actual,
          completionStatus: actual == null
              ? ClassroomCompletionStatus.notAttended
              : ClassroomCompletionStatus.incomplete,
          createdAt: DateTime(2025),
        );

  final List<Consumable> consumables;
  final bool photosFail;
  final _changes = StreamController<List<Classroom>>.broadcast();
  Classroom room;
  String? lastEditId;

  @override
  Stream<List<School>> watchSchools({List<String>? schoolIds}) => Stream.value([
        School(
            id: 'school', name: 'Oakfield Primary', createdAt: DateTime(2025))
      ]);

  @override
  Stream<List<YearLevel>> watchYearLevels(String schoolId) => Stream.value(
      [YearLevel(id: 'level', label: 'Year 1', createdAt: DateTime(2025))]);

  @override
  Stream<List<Classroom>> watchClassrooms(
      String schoolId, String yearLevelId) async* {
    yield [room];
    yield* _changes.stream;
  }

  @override
  Stream<PackTotal?> watchLatestPackTotal(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value(PackTotal(id: 'pack', total: 24, createdAt: DateTime(2025)));

  @override
  Stream<List<Consumable>> watchClassroomConsumables(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value(consumables);

  @override
  Stream<List<YearLevelBreakdown>> watchYearLevelBreakdowns(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value(const []);

  @override
  Stream<List<Note>> watchClassroomNotes(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value(const []);

  @override
  Stream<List<Photo>> watchClassroomPhotos(
          String schoolId, String yearLevelId, String classroomId,
          {String? deliveryId}) =>
      photosFail ? Stream.error(StateError('offline')) : Stream.value(const []);

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
    );
    _changes.add([room]);
    return Result.success((
      status: ClassroomEditStatus.saved,
      acknowledgment: Future.value(const Result.success(null)),
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
