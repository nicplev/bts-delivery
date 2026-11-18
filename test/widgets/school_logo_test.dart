import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/delivery.dart';
import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/school_timer.dart';
import 'package:bts_delivery_app/models/signoff_snapshot.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/pre_delivery_checklist_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/providers/schools_providers.dart';
import 'package:bts_delivery_app/providers/visit_signoff_providers.dart';
import 'package:bts_delivery_app/repositories/deliveries_repository.dart';
import 'package:bts_delivery_app/repositories/schools_repository.dart';
import 'package:bts_delivery_app/repositories/storage_repository.dart';
import 'package:bts_delivery_app/screens/admin/admin_page.dart';
import 'package:bts_delivery_app/screens/main/deliveries_screen.dart';
import 'package:bts_delivery_app/screens/main/schools_screen.dart';
import 'package:bts_delivery_app/services/image_service.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/services/photo_service.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:bts_delivery_app/widgets/info_tab.dart';
import 'package:bts_delivery_app/widgets/school_logo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A 1×1 red PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==');
final _logoImage = MemoryImage(_png);
final _brokenImage = MemoryImage(Uint8List.fromList([1, 2, 3, 4]));

const _logoKey = ValueKey('school-logo-image');
const _oldPath = 'schools/oakfield/logo/11111111-1111-1111-1111-111111111111.jpg';
final _uuidJpg = RegExp(r'^schools/oakfield/logo/[a-f0-9-]{36}\.jpg$');
final _created = DateTime(2026, 11, 1);

School _school({bool logo = false, String id = 'oakfield', String? name}) =>
    School(
      id: id,
      name: name ?? 'Oakfield Primary',
      address: '12 Oakfield Road, Brunswick VIC 3056',
      createdAt: _created,
      logoUrl: logo ? 'https://logo.test/$id.jpg' : null,
      logoStoragePath: logo ? _oldPath : null,
    );

Future<void> _precache(WidgetTester tester, ImageProvider image) =>
    tester.runAsync(() async {
      final element = tester.element(find.byType(Overlay).first);
      await precacheImage(image, element, onError: (_, __) {});
    });

void main() {
  group('School model', () {
    test('round-trips the optional logo fields', () {
      final withLogo = _school(logo: true);
      final json = withLogo.toJson();
      expect(json['logoUrl'], 'https://logo.test/oakfield.jpg');
      expect(json['logoStoragePath'], _oldPath);
      expect(School.fromJson(json), withLogo);
    });

    test('old school documents without logo fields still load', () {
      final school = School.fromJson({
        'id': 'old',
        'name': 'Old School',
        'createdAt': Timestamp.fromDate(_created),
        'schoolMapUrl': 'https://map.test/old.png',
      });
      expect(school.logoUrl, isNull);
      expect(school.logoStoragePath, isNull);
      expect(school.schoolMapUrl, 'https://map.test/old.png');
      expect(School.fromJson(school.toJson()), school);
    });
  });

  group('prepareSchoolLogo', () {
    Future<Uint8List> pngOf(int width, int height) async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..color = const ui.Color(0xFF2266AA));
      final image = await recorder.endRecording().toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    testWidgets('scales the longest side to 512 and never enlarges',
        (tester) async {
      await tester.runAsync(() async {
        final sizes = <(int, int, int)>[];
        Future<Uint8List> encode(Uint8List png, int w, int h, int q) async {
          sizes.add((w, h, q));
          return Uint8List.fromList([0xFF, 0xD8, 0xFF]);
        }

        final wide = await ImageService.prepareSchoolLogo(
            await pngOf(1000, 500),
            encodeJpeg: encode);
        final small = await ImageService.prepareSchoolLogo(
            await pngOf(100, 80),
            encodeJpeg: encode);
        final broken = await ImageService.prepareSchoolLogo(
            Uint8List.fromList([1, 2, 3]),
            encodeJpeg: encode);
        expect(wide.isSuccess, isTrue);
        expect(small.isSuccess, isTrue);
        expect(broken.isSuccess, isFalse);
        expect(sizes, [(512, 256, 85), (100, 80, 85)]);
      });
    });
  });

  group('AppSchoolAvatar', () {
    Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('shows the default icon tile without a logo', (tester) async {
      await tester.pumpWidget(host(const AppSchoolAvatar(size: 48)));
      expect(find.byType(AppIconTile), findsOneWidget);
      expect(find.byIcon(AppIcons.school), findsOneWidget);
      expect(tester.getSize(find.byType(AppSchoolAvatar)), const Size(48, 48));
    });

    testWidgets('shows the logo at the icon tile sizes', (tester) async {
      await tester.pumpWidget(host(const SizedBox()));
      await _precache(tester, _logoImage);
      for (final size in [29.0, 40.0, 48.0]) {
        await tester.pumpWidget(host(
          AppSchoolAvatar(logo: _logoImage, size: size),
          theme: AppTheme.darkTheme,
        ));
        await tester.pump();
        expect(find.byKey(_logoKey), findsOneWidget);
        expect(find.byType(AppIconTile), findsNothing);
        expect(tester.getSize(find.byType(AppSchoolAvatar)), Size(size, size));
      }
      // Decorative unless a label is given.
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(AppSchoolAvatar(
          logo: _logoImage, semanticLabel: 'Logo of Oakfield Primary')));
      await tester.pump();
      expect(find.bySemanticsLabel('Logo of Oakfield Primary'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('falls back to the icon tile while loading and on error',
        (tester) async {
      await tester.pumpWidget(host(AppSchoolAvatar(logo: _brokenImage)));
      // Loading: the icon tile, same size, no spinner.
      expect(find.byType(AppIconTile), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getSize(find.byType(AppSchoolAvatar)), const Size(40, 40));
      await _precache(tester, _brokenImage);
      await tester.pump();
      expect(find.byType(AppIconTile), findsOneWidget);
      expect(find.byKey(_logoKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Info tab logo row', () {
    testWidgets('editors add a logo: uploaded as a JPEG, saved, announced',
        (tester) async {
      final env = _Env(_school());
      await env.pumpInfo(tester);

      expect(find.byKey(const ValueKey('school-logo-editor')), findsOneWidget);
      expect(find.text('No logo. The school icon shows instead.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('school-logo-remove')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('school-logo-add')));
      await tester.pumpAndSettle();

      expect(env.storage.uploads.single, matches(_uuidJpg));
      final path = env.storage.uploads.single;
      expect(env.schools.school.logoStoragePath, path);
      expect(env.schools.school.logoUrl, 'https://storage.test/$path');
      expect(env.storage.deleted, isEmpty);
      expect(find.text('School logo updated'), findsOneWidget);
      expect(find.text('Replace logo'), findsOneWidget);
      expect(find.text('Remove logo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('replacing a logo deletes the old file after saving',
        (tester) async {
      final env = _Env(_school(logo: true));
      await env.pumpInfo(tester);

      await tester.tap(find.byKey(const ValueKey('school-logo-replace')));
      await tester.pumpAndSettle();
      expect(env.schools.school.logoStoragePath, env.storage.uploads.single);
      expect(env.storage.deleted, [_oldPath]);
      expect(find.text('School logo updated'), findsOneWidget);
    });

    testWidgets('a failed upload changes nothing and says so', (tester) async {
      final env = _Env(_school(logo: true), uploadFails: true);
      await env.pumpInfo(tester);

      await tester.tap(find.byKey(const ValueKey('school-logo-replace')));
      await tester.pumpAndSettle();
      expect(env.schools.school.logoStoragePath, _oldPath);
      expect(env.storage.deleted, isEmpty);
      expect(find.text('Couldn’t upload the school logo. Try again.'),
          findsOneWidget);
    });

    testWidgets('removing asks first, then deletes the file and clears it',
        (tester) async {
      final env = _Env(_school(logo: true));
      await env.pumpInfo(tester);

      await tester.tap(find.byKey(const ValueKey('school-logo-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove school logo?'), findsOneWidget);
      final remove =
          find.byKey(const ValueKey('confirm-remove-school-logo'));
      final style = tester.widget<FilledButton>(remove).style!;
      final palette = AppPalette.of(tester.element(remove));
      expect(style.backgroundColor!.resolve({}), palette.error);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(env.storage.deleted, isEmpty);

      await tester.tap(find.byKey(const ValueKey('school-logo-remove')));
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(env.storage.deleted, [_oldPath]);
      expect(env.schools.school.logoUrl, isNull);
      expect(env.schools.school.logoStoragePath, isNull);
      expect(find.text('School logo removed'), findsOneWidget);
      expect(find.text('Add logo'), findsOneWidget);
    });

    testWidgets('people who cannot edit see the logo but no logo controls',
        (tester) async {
      final env = _Env(_school(logo: true), canEdit: false);
      await env.pumpInfo(tester);

      expect(find.byKey(const ValueKey('school-logo-editor')), findsNothing);
      expect(find.text('Add logo'), findsNothing);
      expect(find.text('Replace logo'), findsNothing);
      // The school name row shows the logo in place of the icon.
      expect(find.byKey(_logoKey), findsOneWidget);
    });

    testWidgets('logo row fits 320 pt at 200 % text', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = _Env(_school(logo: true));
      await env.pumpInfo(tester,
          textScale: 2, theme: AppTheme.highContrastDarkTheme);
      expect(tester.takeException(), isNull);

      for (final key in ['school-logo-replace', 'school-logo-remove']) {
        final button = find.byKey(ValueKey(key));
        await tester.ensureVisible(button);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
        expect(tester.getTopRight(button).dx, lessThanOrEqualTo(320));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Today and Schools', () {
    testWidgets('the hero card and a later row show school logos',
        (tester) async {
      final env = _Env(_school(logo: true), others: [
        _school(id: 'riverside', name: 'Riverside School', logo: true),
      ]);
      await env.pumpToday(tester);

      final logos = find.byKey(_logoKey);
      expect(logos, findsNWidgets(2));
      expect(tester.getSize(logos.first), const Size(48, 48));
      expect(tester.getSize(logos.last), const Size(29, 29));
      expect(tester.takeException(), isNull);
    });

    testWidgets('visits of schools without a logo keep the icon tile',
        (tester) async {
      final env = _Env(_school(logo: true), others: [
        _school(id: 'riverside', name: 'Riverside School'),
      ]);
      await env.pumpToday(tester);
      expect(find.byKey(_logoKey), findsOneWidget);
      final rowTile = find.descendant(
          of: find.byKey(const ValueKey('second')),
          matching: find.byType(AppIconTile));
      expect(rowTile, findsWidgets);
    });

    testWidgets('today fits 320 pt at 200 % text with a logo', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = _Env(_school(logo: true), others: [
        _school(id: 'riverside', name: 'Riverside School', logo: true),
      ]);
      await env.pumpToday(tester, textScale: 2);
      expect(find.byKey(_logoKey), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('schools list rows show the logo or the icon tile',
        (tester) async {
      final env = _Env(_school(logo: true), others: [
        _school(id: 'riverside', name: 'Riverside School'),
      ]);
      await env.pumpSchools(tester);
      final logo = find.byKey(_logoKey);
      expect(logo, findsOneWidget);
      expect(tester.getSize(logo), const Size(29, 29));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('riverside')),
              matching: find.byType(AppIconTile)),
          findsOneWidget);

      // Admins manage the logo inside the edit-school dialog.
      await tester.tap(find.byType(AdminOptionsButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit school'), findsOneWidget);
      expect(find.text('Replace logo'), findsOneWidget);
      await tester.tap(find.text('Remove logo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-remove-school-logo')));
      await tester.pumpAndSettle();
      expect(env.schools.school.logoUrl, isNull);
      expect(find.text('Add logo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Env {
  _Env(
    School school, {
    this.canEdit = true,
    bool uploadFails = false,
    List<School> others = const [],
  })  : schools = _Schools(school, others),
        storage = _Storage(fail: uploadFails);

  final _Schools schools;
  final _Storage storage;
  final bool canEdit;

  List<Override> get overrides => [
        authStateProvider.overrideWith((_) => Stream.value(_User())),
        currentStaffProvider.overrideWith((_) => Stream.value(Staff(
              id: 'staff',
              uid: 'owner',
              name: 'Robin',
              role: canEdit ? 'admin' : 'staff',
              assignedSchoolIds: const ['oakfield', 'riverside'],
              createdAt: _created,
            ))),
        isAdminProvider.overrideWithValue(canEdit),
        baseSchoolsRepositoryProvider.overrideWithValue(schools),
        storageRepositoryProvider.overrideWithValue(storage),
        photoServiceProvider.overrideWithValue(_Photos()),
        schoolLogoImageResolverProvider.overrideWithValue((url, key) {
          expect(key, startsWith('school-logo/owner/'));
          return _logoImage;
        }),
        connectivityStatusProvider
            .overrideWith((_) => Stream.value(ConnectivityStatus.online)),
      ];

  Widget _wrap(Widget child, double textScale, ThemeData? theme,
          {List<Override> extra = const []}) =>
      ProviderScope(
        overrides: [...overrides, ...extra],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: child,
        ),
      );

  Future<void> pumpInfo(WidgetTester tester,
      {double textScale = 1, ThemeData? theme}) async {
    await tester.pumpWidget(_wrap(
      const Scaffold(body: InfoTab(schoolId: 'oakfield')),
      textScale,
      theme,
    ));
    await _precache(tester, _logoImage);
    await tester.pumpAndSettle();
  }

  Future<void> pumpSchools(WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const SchoolsScreen(), 1, null, extra: [
      schoolsProvider.overrideWith((ref) => schools.watchSchools()),
    ]));
    await _precache(tester, _logoImage);
    await tester.pumpAndSettle();
  }

  Future<void> pumpToday(WidgetTester tester, {double textScale = 1}) async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const DeliveriesScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overrides,
        isAdminProvider.overrideWithValue(false),
        deliveriesRepositoryProvider.overrideWithValue(_Deliveries(day)),
        evidenceUploadsProvider.overrideWith((_) => Stream.value(
            const EvidenceUploadStatus(
                items: [],
                activeId: null,
                legacyReviewCount: 0,
                localError: false))),
        deliveryChecklistStatusProvider
            .overrideWith((_, __) => const AsyncValue.data(false)),
        visitSignedEvidenceProvider.overrideWith(
            (_, DeliveryVisit visit) => Stream<SignedEvidence?>.value(null)),
        activePreDeliveryChecklistItemsProvider
            .overrideWith((_) => Stream.value(const [])),
        deliveryCompletionsProvider
            .overrideWith((_, __) => Stream.value(const [])),
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
    ));
    await _precache(tester, _logoImage);
    await tester.pumpAndSettle();
  }
}

class _User implements User {
  @override
  String get uid => 'owner';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Photos implements PhotoService {
  @override
  Future<Uint8List?> pickSchoolLogo(BuildContext context) async =>
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements StorageRepository {
  _Storage({required this.fail});

  final bool fail;
  final uploads = <String>[];
  final deleted = <String>[];

  @override
  Future<Result<String>> uploadJpegBytes(String path, Uint8List bytes) async {
    if (fail) return const Result.failure('offline');
    uploads.add(path);
    return Result.success('https://storage.test/$path');
  }

  @override
  Future<Result<void>> deleteFile(String path) async {
    deleted.add(path);
    return const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Schools implements SchoolsRepository {
  _Schools(this.school, this.others);

  School school;
  final List<School> others;
  final _changes = StreamController<void>.broadcast();

  List<School> get _all => [school, ...others];

  @override
  Stream<List<School>> watchSchools({List<String>? schoolIds}) async* {
    List<School> pick() => [
          for (final s in _all)
            if (schoolIds == null || schoolIds.contains(s.id)) s,
        ];
    yield pick();
    await for (final _ in _changes.stream) {
      yield pick();
    }
  }

  @override
  Future<Result<void>> updateSchoolLogo(
    String schoolId, {
    required String? logoUrl,
    required String? logoStoragePath,
  }) async {
    school =
        school.copyWith(logoUrl: logoUrl, logoStoragePath: logoStoragePath);
    _changes.add(null);
    return const Result.success(null);
  }

  @override
  Stream<List<Contact>> watchContacts(String schoolId) =>
      Stream.value(const []);

  @override
  Stream<List<SchoolTimer>> watchTimerHistory(String schoolId,
          {int limit = 20}) =>
      Stream.value(const []);

  @override
  Stream<SchoolTimer?> watchActiveTimer(String schoolId) => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Deliveries implements DeliveriesRepository {
  _Deliveries(this.today);

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
        id: 'first',
        schoolId: 'oakfield',
        schoolName: 'Oakfield Primary',
        date: today,
        time: today.add(const Duration(hours: 9)),
        palletCount: 4,
        createdAt: today,
      ),
      Delivery(
        id: 'second',
        schoolId: 'riverside',
        schoolName: 'Riverside School',
        date: today,
        time: today.add(const Duration(hours: 13, minutes: 30)),
        palletCount: 2,
        createdAt: today,
      ),
    ]);
  }

  @override
  Future<Result<List<Staff>>> getAllStaff() async => const Result.success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
