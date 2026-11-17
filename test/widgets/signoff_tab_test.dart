import 'dart:async';

import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/checklist_item.dart';
import 'package:bts_delivery_app/models/offline/evidence_upload.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/signoff_snapshot.dart';
import 'package:bts_delivery_app/providers/checklist_providers.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/repositories/schools_repository.dart';
import 'package:bts_delivery_app/repositories/storage_repository.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:bts_delivery_app/widgets/signoff_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const emptyQueue = EvidenceUploadStatus(
    items: [],
    activeId: null,
    legacyReviewCount: 0,
    localError: false,
  );

  Future<void> pumpTab(
    WidgetTester tester, {
    SignedEvidence? signed,
    EvidenceUploadStatus queue = emptyQueue,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseSchoolsRepositoryProvider
              .overrideWithValue(_SignOffSchools(signed)),
          storageRepositoryProvider.overrideWithValue(_NoStorage()),
          evidenceUploadsProvider.overrideWith((_) => Stream.value(queue)),
          activeChecklistItemsProvider
              .overrideWith((_) => Stream.value(const <ChecklistItem>[])),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          home: const Scaffold(
            body: SignOffTab(
              schoolId: 'school',
              schoolName: 'Oakfield Primary',
              deliveryId: 'visit',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void phone(WidgetTester tester, {bool small = false}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize =
        small ? const Size(320, 640) : const Size(390, 844);
    if (small) tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('review leads with classrooms that need attention', (
    tester,
  ) async {
    phone(tester);
    await pumpTab(tester);

    expect(find.text('23'), findsOneWidget);
    expect(find.text('of 46 packs recorded'), findsOneWidget);
    expect(find.text('23 packs outstanding in 2 classrooms'), findsOneWidget);
    expect(find.text('Year 1 · Rest due next visit'), findsOneWidget);
    expect(find.text('13 of 24'), findsOneWidget);
    expect(find.text('Year 2 · Not attended'), findsOneWidget);
    expect(find.text('0 of 12'), findsOneWidget);
    // Complete classrooms stay behind the summary row until expanded.
    expect(find.text('Room P'), findsNothing);

    final primary = find.widgetWithText(
      AppGlassPrimaryButton,
      'Continue to signature',
    );
    expect(primary, findsOneWidget);
    expect(find.text('View visit history'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('2 attached'), findsOneWidget);
    expect(find.text('Classroom notes'), findsOneWidget);
    expect(find.text('Rest due next visit'), findsOneWidget);

    final toggle = find.text('1 classroom complete');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Room P'), findsOneWidget);
    expect(find.text('10 expected packs'), findsOneWidget);
    expect(find.text('13 of 24 packs delivered'), findsOneWidget);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Room P'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed record shows the saved state and its actions', (
    tester,
  ) async {
    phone(tester);
    await pumpTab(tester, signed: _signed());

    expect(find.text('Signed record'), findsOneWidget);
    expect(
      find.textContaining('Saved to server.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Taylor Morgan'), findsOneWidget);
    expect(find.text('23 of 46'), findsOneWidget);
    // In the record card and in the current records summary.
    expect(find.text('23 packs outstanding in 2 classrooms'), findsNWidgets(2));
    expect(find.text('2 included'), findsOneWidget);
    expect(find.text('Signature image unavailable'), findsOneWidget);
    expect(
      find.widgetWithText(AppGlassPrimaryButton, 'Export summary'),
      findsOneWidget,
    );
    expect(find.text('Continue to signature'), findsNothing);
    expect(find.text('View visit history'), findsOneWidget);

    final correction = find.text('Sign a correction');
    await tester.ensureVisible(correction);
    await tester.tap(correction);
    await tester.pumpAndSettle();
    expect(find.text('Signed record'), findsNothing);
    expect(find.text('Continue to signature'), findsOneWidget);

    final cancel = find.text('Cancel correction');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('Signed record'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a queued signature is shown as saved on this device', (
    tester,
  ) async {
    phone(tester);
    await pumpTab(
      tester,
      queue: EvidenceUploadStatus(
        items: [
          EvidenceUpload(
            id: 'queued',
            kind: EvidenceKind.signature,
            ownerUid: 'owner',
            schoolId: 'school',
            deliveryId: 'visit',
            localFileName: 'pending_evidence/queued.png',
            storagePath: 'schools/school/signoffs/queued.png',
            createdAt: DateTime(2026, 11, 17),
            paused: true,
          ),
        ],
        activeId: null,
        legacyReviewCount: 0,
        localError: false,
      ),
    );

    expect(find.text('Signature saved on this device'), findsOneWidget);
    expect(find.text('Paused on this device'), findsOneWidget);
    expect(find.text('Continue to signature'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
    ('high-contrast dark', AppTheme.highContrastDarkTheme),
  ]) {
    testWidgets('review and signed record fit 320 pt at 200 % text ($name)', (
      tester,
    ) async {
      phone(tester, small: true);
      await pumpTab(tester, theme: theme);
      // The action moves into the content at large text sizes.
      expect(find.byType(AppGlassPrimaryButton), findsNothing);
      expect(
        find.widgetWithText(AppPrimaryButton, 'Continue to signature'),
        findsOneWidget,
      );
      final toggle = find.text('1 classroom complete');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('View notes'), findsWidgets);
      expect(tester.takeException(), isNull);

      await pumpTab(tester, signed: _signed(), theme: theme);
      expect(find.text('Signed record'), findsOneWidget);
      expect(
        find.widgetWithText(AppPrimaryButton, 'Export summary'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

SignedEvidence _signed() {
  final base = SignOffSnapshot.incomplete('school').summary;
  return SignedEvidence(
    id: 'evidence',
    schoolId: 'school',
    deliveryId: 'visit',
    ownerUid: 'owner',
    signaturePath: 'schools/school/signoffs/evidence.png',
    typedName: 'Taylor Morgan',
    capturedAt: DateTime.utc(2026, 11, 17, 10, 48),
    snapshot: SignOffSnapshot(
      sourceReadAt: DateTime.utc(2026, 11, 17, 10, 40),
      serverReviewed: true,
      summary: {
        ...base,
        'totalPacks': 46,
        'photoUrls': ['a.jpg', 'b.jpg'],
        'classroomDeliveryDetails': [
          {
            'yearLevel': 'Year 1',
            'classroomName': 'Room 1A',
            'status': 'incomplete',
            'expectedPacks': 24,
            'actualPacksDelivered': 13,
            'consumables': <String, dynamic>{},
          },
          {
            'yearLevel': 'Year 2',
            'classroomName': 'Room 2A',
            'status': 'notAttended',
            'expectedPacks': 12,
            'actualPacksDelivered': null,
            'consumables': <String, dynamic>{},
          },
          {
            'yearLevel': 'Prep',
            'classroomName': 'Room P',
            'status': 'complete',
            'expectedPacks': 10,
            'actualPacksDelivered': null,
            'consumables': <String, dynamic>{},
          },
        ],
      },
    ),
  );
}

class _SignOffSchools implements SchoolsRepository {
  _SignOffSchools(this.signed);

  final SignedEvidence? signed;
  final _created = DateTime(2026, 11, 1);

  late final _years = [
    YearLevel(id: 'prep', label: 'Prep', createdAt: _created),
    YearLevel(id: 'y1', label: 'Year 1', createdAt: _created),
    YearLevel(id: 'y2', label: 'Year 2', createdAt: _created),
  ];

  late final _rooms = {
    'prep': Classroom(
      id: 'p',
      name: 'Room P',
      createdAt: _created,
      completionStatus: ClassroomCompletionStatus.complete,
    ),
    'y1': Classroom(
      id: '1a',
      name: 'Room 1A',
      createdAt: _created,
      completionStatus: ClassroomCompletionStatus.incomplete,
      actualPacksDelivered: 13,
    ),
    'y2': Classroom(id: '2a', name: 'Room 2A', createdAt: _created),
  };

  static const _expected = {'p': 10, '1a': 24, '2a': 12};

  @override
  Stream<List<YearLevel>> watchYearLevels(String schoolId) =>
      Stream.value(_years);

  @override
  Stream<List<Classroom>> watchClassrooms(
          String schoolId, String yearLevelId) =>
      Stream.value([_rooms[yearLevelId]!]);

  @override
  Stream<PackTotal?> watchLatestPackTotal(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value(PackTotal(
          id: 'total', total: _expected[classroomId]!, createdAt: _created));

  @override
  Stream<List<Consumable>> watchClassroomConsumables(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value(const []);

  @override
  Stream<List<YearLevelBreakdown>> watchYearLevelBreakdowns(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value(const []);

  @override
  Stream<List<Note>> watchClassroomNotes(
          String schoolId, String yearLevelId, String classroomId) =>
      Stream.value([
        if (classroomId == '1a')
          Note(id: 'n', content: 'Rest due next visit', createdAt: _created),
      ]);

  @override
  Stream<List<Photo>> watchClassroomPhotos(
          String schoolId, String yearLevelId, String classroomId,
          {String? deliveryId}) =>
      Stream.value([
        if (classroomId == '1a')
          for (final id in ['a', 'b'])
            Photo(id: id, storagePath: '$id.jpg', uploadedAt: _created),
      ]);

  @override
  Stream<List<Note>> watchNotes(String schoolId) => Stream.value(const []);

  @override
  Stream<SignOff?> watchSignOff(String schoolId) => Stream.value(null);

  @override
  Stream<SignedEvidence?> watchSignedEvidence(
          String schoolId, String? deliveryId) =>
      Stream.value(signed);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoStorage implements StorageRepository {
  @override
  Future<Result<String>> getDownloadUrl(String path) async =>
      const Result.failure('unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
