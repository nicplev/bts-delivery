import 'dart:async';
import 'dart:io';

import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/offline/evidence_upload.dart';
import 'package:bts_delivery_app/models/offline/offline_media.dart';
import 'package:bts_delivery_app/models/photo_subject.dart';
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
import 'package:bts_delivery_app/services/media/offline_media_cache.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/offline/field_draft_store.dart';
import 'package:bts_delivery_app/services/photo_service.dart';
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
      '320 pt at 200 % text: no overflow and Record packs sits inline '
      'after the packs card', (tester) async {
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

    // At large text "Record packs" follows the packs card instead of
    // floating over the content.
    expect(find.byType(AppGlassPrimaryButton), findsNothing);
    final packs = tester.getRect(find.text('Pack delivery status'));
    final inline = tester.getRect(find.byKey(const ValueKey('record-packs')));
    expect(inline.top, greaterThan(packs.bottom));

    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No notes yet'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 6000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('record-packs')));
    await tester.pumpAndSettle();
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

  testWidgets(
      'a differing consumable quantity is an amber warning; delivered stays '
      'neutral', (tester) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final schools = _Schools(actual: 13, consumables: [
        Consumable(
          id: 'tissues',
          itemName: 'Tissues',
          quantity: 12,
          unit: 'boxes',
          actualQuantityDelivered: 12,
          createdAt: DateTime(2025),
        ),
        Consumable(
          id: 'paper',
          itemName: 'Copy paper',
          quantity: 6,
          unit: 'reams',
          actualQuantityDelivered: 3,
          createdAt: DateTime(2025),
        ),
      ]);
      await _pumpRoom(tester, schools, theme: theme);
      final pill = find.byKey(const ValueKey('consumable-quantity-differs'));
      await tester.dragUntilVisible(
          pill, find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(pill, findsOneWidget);
      expect(find.text('3 / 6 reams'), findsOneWidget);
      final palette = AppPalette.of(tester.element(pill));
      final status = tester.widget<AppStatusPill>(
          find.descendant(of: pill, matching: find.byType(AppStatusPill)));
      expect(status.tone, AppTone.warning);
      expect(status.icon, AppIcons.warning);
      expect(
        find.descendant(
          of: pill,
          matching: find.byWidgetPredicate((widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration).color ==
                  palette.warningTint),
        ),
        findsOneWidget,
      );
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: pill, matching: find.text('Quantity differs')))
              .style
              ?.color,
          palette.warningInk);
      expect(find.bySemanticsLabel(RegExp('Quantity differs')), findsOneWidget);

      // Delivered as expected keeps the neutral solid check.
      expect(find.text('12 / 12 boxes'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      final delivered = tester.widget<AppStatusRing>(find.byWidgetPredicate(
          (widget) =>
              widget is AppStatusRing && widget.semanticLabel == 'Delivered'));
      expect(delivered.status, AppCompletion.complete);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'a photo taken from a card is attached to that item and previewed on '
      'it; the section add makes a general photo', (tester) async {
    final worker = _Worker();
    await _pumpRoom(tester, _Schools(actual: 13, consumables: [_tissues]),
        worker: worker);
    expect(find.text('No photos'), findsNWidgets(2));
    expect(find.text('No other photos'), findsOneWidget);

    // Packs card.
    final addPacks = find.bySemanticsLabel('Add photo of packs');
    await _reveal(tester, addPacks);
    await tester.tap(addPacks);
    await tester.pumpAndSettle();
    expect(worker.items.single.subject, PhotoSubject.packs);
    expect(find.text('Photo saved on this device'), findsOneWidget);
    final packsStrip = find.byKey(const ValueKey('photo-strip-packs'));
    expect(packsStrip, findsOneWidget);
    expect(
        find.descendant(
            of: packsStrip,
            matching: find.bySemanticsLabel('Photo of packs, waiting to upload')),
        findsOneWidget);
    expect(find.text('1 photo'), findsOneWidget);
    expect(find.text('1 waiting to upload'), findsOneWidget);

    // Consumable card.
    final addTissues = find.bySemanticsLabel('Add photo of Tissues');
    await _reveal(tester, addTissues);
    await tester.tap(addTissues);
    await tester.pumpAndSettle();
    expect(worker.items.last.subject,
        PhotoSubject.consumable(id: 'tissues', label: 'Tissues'));
    final tissuesStrip = find.byKey(const ValueKey('photo-strip-tissues'));
    expect(
        find.descendant(
            of: tissuesStrip,
            matching:
                find.bySemanticsLabel('Photo of Tissues, waiting to upload')),
        findsOneWidget);
    expect(find.descendant(of: packsStrip, matching: find.byType(Image)),
        findsOneWidget);
    expect(find.text('1 waiting to upload'), findsNWidgets(2));

    // "Other photos" adds an unattached photo.
    final addOther = find.bySemanticsLabel('Add photo');
    await _reveal(tester, addOther.first);
    await tester.tap(addOther.first);
    await tester.pumpAndSettle();
    expect(worker.items.last.subject, isNull);
    expect(worker.items.last.hasSubject, isFalse);
    expect(find.text('No other photos'), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('photo-strip-other')),
            matching: find.bySemanticsLabel(
                'Classroom photo, waiting to upload')),
        findsOneWidget);
    expect(worker.items, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saved photos group by item; a removed item\'s photos stay under Other '
      'photos with its saved name', (tester) async {
    final schools = _Schools(actual: 13, consumables: [
      _tissues,
      _paper,
    ], photos: [
      _photo('packs-1', subject: PhotoSubject.packs, minute: 9),
      _photo('tissues-1',
          subject: PhotoSubject.consumable(id: 'tissues', label: 'Tissues'),
          minute: 8),
      _photo('tissues-2',
          subject: PhotoSubject.consumable(id: 'tissues', label: 'Tissue'),
          minute: 7),
      _photo('old-1', minute: 6),
      _photo('removed-1',
          subject: PhotoSubject.consumable(id: 'gone', label: 'Headphones'),
          minute: 5),
    ]);
    await _pumpRoom(tester, schools, worker: _Worker());

    Finder inStrip(String key, String label) => find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.bySemanticsLabel(label));

    expect(inStrip('photo-strip-packs', 'Photo of packs, 1 of 1'),
        findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
    expect(inStrip('photo-strip-tissues', 'Photo of Tissues, 1 of 2'),
        findsOneWidget);
    // Renamed after the photo was taken: still on the same card.
    expect(inStrip('photo-strip-tissues', 'Photo of Tissues, 2 of 2'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('photo-strip-paper')), findsNothing);
    final other = find.byKey(const ValueKey('photo-strip-other'));
    await tester.scrollUntilVisible(other, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(inStrip('photo-strip-other', 'Classroom photo, 1 of 1'),
        findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Headphones (removed item)'), findsOneWidget);
    expect(
        inStrip('photo-strip-removed-gone',
            'Photo of Headphones (removed item), 1 of 1'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a strip scrolls sideways, a vertical drag on it scrolls the page, and '
      'remove keeps its confirmation', (tester) async {
    final schools = _Schools(actual: 13, photos: [
      for (var i = 0; i < 15; i++)
        _photo('packs-$i', subject: PhotoSubject.packs, minute: 20 - i),
    ]);
    await _pumpRoom(tester, schools, worker: _Worker());
    final strip = find.byKey(const ValueKey('photo-strip-packs'));
    await _reveal(tester, strip);
    expect(find.bySemanticsLabel('Photo of packs, 1 of 15'), findsOneWidget);
    ScrollPosition position() => tester
        .state<ScrollableState>(find
            .descendant(of: strip, matching: find.byType(Scrollable))
            .first)
        .position;
    final stripTop = tester.getTopLeft(strip).dy;

    await tester.drag(strip, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(150));
    expect(tester.getTopLeft(strip).dy, stripTop);

    final pixels = position().pixels;
    await tester.drag(strip, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(strip).dy, greaterThan(stripTop + 100));
    expect(position().pixels, pixels);

    await _reveal(tester, strip);
    await tester.drag(strip, const Offset(400, 0));
    await tester.pumpAndSettle();
    final remove = find.descendant(
        of: strip, matching: find.bySemanticsLabel('Remove from classroom'));
    expect(remove, findsWidgets);
    await tester.tap(remove.first);
    await tester.pumpAndSettle();
    expect(find.text('Remove photo from classroom?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(schools.deletedPhotos, isEmpty);

    await tester.tap(remove.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(schools.deletedPhotos, ['packs-0']);
    expect(find.text('Photo removed from classroom'), findsOneWidget);
    expect(find.text('14 photos'), findsOneWidget);
  });

  testWidgets('photos at 320 pt and 200 % text, dark and high contrast',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (theme, scale) in [
      (AppTheme.lightTheme, 2.0),
      (AppTheme.darkTheme, 1.0),
      (AppTheme.highContrastLightTheme, 1.0),
      (AppTheme.highContrastDarkTheme, 2.0),
    ]) {
      // A fresh provider scope for each theme.
      await tester.pumpWidget(const SizedBox());
      final worker = _Worker();
      final schools = _Schools(actual: 13, consumables: [
        _tissues.copyWith(itemName: 'Tissues for the whole class, large'),
      ], photos: [
        _photo('packs-1', subject: PhotoSubject.packs),
        _photo('tissues-1',
            subject: PhotoSubject.consumable(id: 'tissues', label: 'Tissues')),
        _photo('old-1'),
      ]);
      await _pumpRoom(tester, schools,
          worker: worker, theme: theme, textScale: scale);
      final add = find.bySemanticsLabel(RegExp('^Add photo of Tissues'));
      await _reveal(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(worker.items.single.subject?.id, 'tissues');
      expect(tester.takeException(), isNull);
      for (final key in ['photo-strip-packs', 'photo-strip-tissues']) {
        final strip = find.byKey(ValueKey(key));
        await tester.ensureVisible(strip);
        await tester.pumpAndSettle();
        expect(tester.getSize(strip).height, 88);
        expect(tester.getRect(strip).right, lessThanOrEqualTo(320));
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -8000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Other photos'), findsOneWidget);
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

/// Scrolls [finder] to the upper part of the page, clear of the floating
/// "Record packs" action.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.3);
  await tester.pumpAndSettle();
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
  _Worker? worker,
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
        if (worker == null) ...[
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
        ] else ...[
          evidenceUploadWorkerProvider.overrideWith((_) async => worker),
          evidenceUploadsProvider.overrideWith((_) => worker.watch()),
          photoServiceProvider.overrideWithValue(_Picker()),
          offlineMediaOwnerProvider.overrideWith((_, __) => 'owner'),
          offlineMediaBucketProvider
              .overrideWithValue('approved.firebasestorage.app'),
          offlineMediaWorkerProvider.overrideWith((_) async => _Cache()),
          offlineMediaAssetStateProvider.overrideWith((_, __) => Stream.value((
                phase: OfflineMediaPhase.available,
                issue: null,
                localPath: null,
                verifiedAt: null,
                progress: null,
              ))),
          isOnlineProvider.overrideWithValue(false),
        ],
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
    this.photos = const [],
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
  List<Photo> photos;
  final deletedPhotos = <String>[];
  final _photoChanges = StreamController<List<Photo>>.broadcast();
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
      photosFail ? Stream.error(StateError('offline')) : _photoStream();

  Stream<List<Photo>> _photoStream() async* {
    yield photos;
    yield* _photoChanges.stream;
  }

  @override
  Future<Result<void>> deleteClassroomPhoto(String schoolId,
      String yearLevelId, String classroomId, String photoId,
      {String? deliveryId}) async {
    deletedPhotos.add(photoId);
    photos = photos.where((photo) => photo.id != photoId).toList();
    _photoChanges.add(photos);
    return const Result.success(null);
  }

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

/// Records photos saved from the classroom screen as queued uploads.
class _Worker implements EvidenceUploadWorker {
  final items = <EvidenceUpload>[];
  final _changes = StreamController<EvidenceUploadStatus>.broadcast();

  @override
  EvidenceUploadStatus get status => EvidenceUploadStatus(
        items: List.of(items),
        activeId: null,
        legacyReviewCount: 0,
        localError: false,
      );

  @override
  Stream<EvidenceUploadStatus> watch() async* {
    yield status;
    yield* _changes.stream;
  }

  @override
  File localFile(EvidenceUpload item) => File('missing/${item.id}.jpg');

  @override
  Future<void> enqueuePhoto({
    required String ownerUid,
    required String schoolId,
    required String yearLevelId,
    required String classroomId,
    required File source,
    String? deliveryId,
    PhotoSubject? subject,
  }) async {
    final id = 'queued-${items.length + 1}';
    items.add(EvidenceUpload(
      id: id,
      kind: EvidenceKind.photo,
      ownerUid: ownerUid,
      schoolId: schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroomId,
      deliveryId: deliveryId,
      localFileName: 'pending_evidence/$id.jpg',
      storagePath: 'path/$id.jpg',
      createdAt: DateTime.utc(2026, 11, 18),
      subjectType: subject?.type,
      subjectId: subject?.id,
      subjectLabel: subject?.label,
    ));
    _changes.add(status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Picker implements PhotoService {
  @override
  Future<File?> pickImage(BuildContext context) async => File('camera.jpg');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements OfflineMediaCache {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _photoPath(String id) =>
    '${_visit.workspacePath}/yearLevels/level/classrooms/room/photos/$id.jpg';

Photo _photo(String id, {PhotoSubject? subject, int minute = 0}) => Photo(
      id: id,
      storagePath: _photoPath(id),
      uploadedBy: 'owner',
      uploadedAt: DateTime(2026, 11, 17, 10, minute),
      subjectType: subject?.type,
      subjectId: subject?.id,
      subjectLabel: subject?.label,
    );

final _tissues = Consumable(
  id: 'tissues',
  itemName: 'Tissues',
  quantity: 12,
  unit: 'boxes',
  createdAt: DateTime(2025),
);

final _paper = Consumable(
  id: 'paper',
  itemName: 'Copy paper',
  quantity: 6,
  unit: 'reams',
  createdAt: DateTime(2025),
);
