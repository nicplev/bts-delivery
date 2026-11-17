import 'dart:async';

import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/offline/evidence_upload.dart';
import 'package:bts_delivery_app/models/offline/offline_media.dart';
import 'package:bts_delivery_app/models/offline/saved_edit.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/delivery_visit_provider.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/offline_media_providers.dart';
import 'package:bts_delivery_app/providers/saved_edit_providers.dart';
import 'package:bts_delivery_app/services/delivery_visit_access.dart';
import 'package:bts_delivery_app/services/media/offline_media_cache.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/widgets/connectivity_indicator.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:bts_delivery_app/widgets/offline_visit_media_panel.dart';
import 'package:bts_delivery_app/widgets/saved_edits_review.dart';
import 'package:bts_delivery_app/widgets/sync_status_detail_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _bucket = 'approved.firebasestorage.app';
const _visit = DeliveryVisit(deliveryId: 'visit-a', schoolId: 'school-a');

OfflineMediaAsset _map() => OfflineMediaAsset.schoolMap(
      bucket: _bucket,
      schoolId: 'school-a',
      reference: 'schools/school-a/map/map.pdf',
      visit: _visit,
    )!;

OfflineMediaAsset _photo(int index) => OfflineMediaAsset.classroomPhoto(
      bucket: _bucket,
      schoolId: 'school-a',
      yearLevelId: 'year-a',
      classroomId: 'room-a',
      photoId: 'photo-$index',
      reference:
          '${_visit.workspacePath}/yearLevels/year-a/classrooms/room-a/photos/photo-$index.jpg',
      visit: _visit,
    )!;

OfflineMediaVisitState _mediaState({int ready = 9, int failed = 0}) => (
      inventory: MediaInventory(
        assets: [_map(), for (var i = 0; i < 12; i++) _photo(i)],
        checkedAt: DateTime.utc(2026, 11, 16, 9),
        unavailableCount: 0,
      ),
      totalAvailable: 13,
      ready: ready,
      waiting: 0,
      failed: failed,
      canRemoveVisitCopies: true,
      savedMap: null,
      localError: false,
      discovering: false,
      clearing: false,
      cancellationStalled: false,
      progress: null,
    );

Widget _app(Widget child,
    {required List<Override> overrides, double textScale = 1}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
}

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<Override> _mediaOverrides(OfflineMediaVisitState state) => [
      offlineMediaOwnerProvider.overrideWith((ref, _) => 'driver'),
      offlineMediaBucketProvider.overrideWithValue(_bucket),
      offlineMediaVisitStateProvider
          .overrideWith((ref, _) => Stream.value(state)),
      offlineMediaAssetStateProvider.overrideWith((ref, asset) => Stream.value((
            phase: asset.kind == OfflineMediaKind.map
                ? OfflineMediaPhase.ready
                : OfflineMediaPhase.available,
            issue: null,
            localPath: null,
            verifiedAt: null,
            progress: null,
          ))),
      offlineMediaWorkerProvider
          .overrideWith((ref) => Completer<OfflineMediaCache>().future),
      isOnlineProvider.overrideWithValue(true),
      deliveryVisitReadinessProvider.overrideWith((ref, _) async =>
          (uid: 'driver', status: DeliveryVisitReadiness.ready)),
    ];

final _school = School(
  id: 'school-a',
  name: 'Oakfield Primary',
  address: '1 School Road',
  createdAt: DateTime(2025),
  schoolMapStoragePath: 'schools/school-a/map/map.pdf',
);

EvidenceUpload _upload(String id,
        {bool paused = false, EvidenceUploadError? error}) =>
    EvidenceUpload(
      id: id,
      kind: EvidenceKind.photo,
      ownerUid: 'driver',
      schoolId: 'school-a',
      localFileName: '$id.jpg',
      storagePath: 'path/$id.jpg',
      createdAt: DateTime.utc(2026, 11, 16),
      paused: paused,
      error: error,
    );

void main() {
  testWidgets(
      'offline files entry states what is left and opens the sheet at 320 pt '
      'with 200 % text', (tester) async {
    _narrow(tester);
    await tester.pumpWidget(_app(
      Align(
        alignment: Alignment.topLeft,
        child: OfflineVisitMediaPanel(visit: _visit, school: _school),
      ),
      overrides: _mediaOverrides(_mediaState()),
      textScale: 2,
    ));
    await tester.pumpAndSettle();

    expect(find.text('4 photos to download'), findsOneWidget);
    expect(find.bySemanticsLabel('Offline files: 4 photos to download'),
        findsOneWidget);
    await tester.tap(find.text('4 photos to download'));
    await tester.pumpAndSettle();

    expect(find.text('Offline files'), findsOneWidget);
    expect(find.text('School map'), findsOneWidget);
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(find.text('8 of 12 saved'), findsOneWidget);
    expect(find.bySemanticsLabel('Classroom photos saved'), findsOneWidget);
    expect(find.text('Available offline'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Download 4 photos'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Download 4 photos'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Clear downloaded media on this device'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Remove downloads'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed downloads show the amber notice and say so in the entry',
      (tester) async {
    await tester.pumpWidget(_app(
      Align(
        alignment: Alignment.topLeft,
        child: OfflineVisitMediaPanel(visit: _visit, school: _school),
      ),
      overrides: _mediaOverrides(_mediaState(failed: 2)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2 files need a new download'), findsOneWidget);

    await tester.tap(find.text('2 files need a new download'));
    await tester.pumpAndSettle();
    final notice = find.ancestor(
      of: find.text('2 files need a new download').last,
      matching: find.byType(AppNotice),
    );
    expect(tester.widget<AppNotice>(notice).warning, isTrue);
  });

  testWidgets('saved edits banner is amber with Review when a decision is due',
      (tester) async {
    _narrow(tester);
    final edits = [
      SavedEdit(_intent('00000000-0000-4000-8000-000000000001'),
          SavedEditState.review),
      SavedEdit(_intent('00000000-0000-4000-8000-000000000002'),
          SavedEditState.waiting),
    ];
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SavedEditsBanner(),
            ),
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_Driver())),
        savedEditsProvider.overrideWith((_) => Stream.value(edits)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 edit to review'), findsOneWidget);
    final palette =
        AppPalette.of(tester.element(find.text('1 edit to review')));
    expect(
      find.byWidgetPredicate((widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == palette.warningTint),
      findsOneWidget,
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Saved edits'), findsOneWidget);
    expect(find.text('Edit to review'), findsOneWidget);
    expect(find.text('Review change'), findsOneWidget);
    // The waiting edit stays neutral and keeps its truthful wording.
    await tester.scrollUntilVisible(find.text('Saved on this device'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'evidence uploads: paused upload is an amber card whose primary action '
      'resumes it', (tester) async {
    _narrow(tester);
    final worker = _Worker();
    await tester.pumpWidget(_app(
      const ConnectivityIndicator(),
      overrides: [
        connectivityStatusProvider
            .overrideWith((_) => Stream.value(ConnectivityStatus.offline)),
        evidenceUploadsProvider.overrideWith((_) => Stream.value(
              EvidenceUploadStatus(
                items: [
                  _upload('paused', paused: true),
                  _upload('waiting'),
                ],
                activeId: null,
                legacyReviewCount: 0,
                localError: false,
              ),
            )),
        evidenceUploadWorkerProvider.overrideWith((_) async => worker),
        isAdminProvider.overrideWithValue(false),
      ],
      textScale: 2,
    ));
    await tester.pumpAndSettle();

    const label = 'Offline · 2 saved on this device · 1 need review';
    expect(find.text(label), findsOneWidget);
    expect(
        find.bySemanticsLabel('$label. Show evidence uploads'), findsOneWidget);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();

    expect(find.text('Evidence uploads'), findsOneWidget);
    expect(find.text('Waiting for a network connection'), findsOneWidget);
    expect(find.text('Upload paused'), findsOneWidget);
    expect(find.textContaining('The original is still on this device.'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('Saved on this device'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Saved on this device'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Resume upload'), -200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Resume upload'));
    await tester.pumpAndSettle();
    expect(worker.retried, ['paused']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('evidence uploads keep the empty state', (tester) async {
    await tester.pumpWidget(_app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => SyncStatusDetailSheet.show(context),
          child: const Text('open'),
        ),
      ),
      overrides: [
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
      ],
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('No photos or signatures waiting to upload.'),
        findsOneWidget);
    expect(find.text('Network connection detected'), findsOneWidget);
  });
}

EditIntent _intent(String id) => EditIntent(
      id: id,
      ownerUid: 'driver',
      schoolId: 'school',
      deliveryId: 'visit',
      yearLevelId: 'year',
      classroomId: 'room',
      kind: SavedEditKind.classroomName,
      capturedAt: DateTime.utc(2026, 11, 16),
      values: {'name': 'Room B'},
      updatedBy: 'Driver',
    );

class _Driver implements User {
  @override
  String get uid => 'driver';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Worker implements EvidenceUploadWorker {
  final retried = <String>[];

  @override
  Future<void> retry(String id) async => retried.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
