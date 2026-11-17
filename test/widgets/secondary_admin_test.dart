import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/checklist_item.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/season_export_models.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/models/user.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/calendar_metadata_provider.dart';
import 'package:bts_delivery_app/providers/checklist_providers.dart';
import 'package:bts_delivery_app/providers/deliveries_providers.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/schools_providers.dart';
import 'package:bts_delivery_app/providers/season_export_providers.dart';
import 'package:bts_delivery_app/repositories/checklist_repository.dart';
import 'package:bts_delivery_app/repositories/season_export_repository.dart';
import 'package:bts_delivery_app/screens/admin/admin_page.dart';
import 'package:bts_delivery_app/screens/admin/checklist_management_screen.dart';
import 'package:bts_delivery_app/screens/admin/season_export_screen.dart';
import 'package:bts_delivery_app/screens/admin/staff_management_screen.dart';
import 'package:bts_delivery_app/screens/main/profile_screen.dart';
import 'package:bts_delivery_app/screens/main/schools_screen.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _admin = Staff(
  id: 'admin',
  uid: 'uid-admin',
  name: 'Robin Administrator with a long name',
  role: 'admin',
  createdAt: DateTime(2026),
);

final _schools = [
  for (var i = 1; i <= 7; i++)
    School(
      id: 'school-$i',
      name: 'Long Example Primary School Number $i',
      address: '$i Long Campus Road, Reception at the south entrance',
      createdAt: DateTime(2026),
    ),
];

/// A 320 pt wide screen at 200 % text in [theme].
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Scrolls the page until [finder] sits in the upper part of the screen,
/// clear of the floating action.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(finder, 80, scrollable: scrollable);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.4);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'schools tab searches, clears and opens school options at 320 pt / 200 %',
      (tester) async {
    await _pump(
      tester,
      const SchoolsScreen(),
      theme: AppTheme.highContrastDarkTheme,
      overrides: [
        isAdminProvider.overrideWithValue(true),
        currentStaffProvider.overrideWith((_) => Stream.value(_admin)),
        schoolsProvider.overrideWith((_) => Stream.value(_schools)),
      ],
    );

    expect(find.text('Schools'), findsOneWidget);
    expect(find.text('7 schools'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'no such school');
    await tester.pumpAndSettle();
    expect(find.text('No schools found'), findsOneWidget);
    expect(find.text('0 of 7 schools'), findsOneWidget);
    await _reveal(tester, find.text('Clear search'));
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text(_schools.first.name), findsOneWidget);

    // Per-school management through the trailing options control.
    await _reveal(tester, find.byType(AdminOptionsButton).first);
    await tester.tap(find.byType(AdminOptionsButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Manage staff'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit school'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Add school / bulk import through the glass add button.
    await tester.tap(find.byType(AppGlassIconButton));
    await tester.pumpAndSettle();
    expect(find.text('Add school'), findsOneWidget);
    expect(find.text('Bulk import CSV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile shows grouped admin rows and confirms sign out',
      (tester) async {
    await _pump(
      tester,
      const ProfileScreen(),
      overrides: [
        isAdminProvider.overrideWithValue(true),
        isManagerProvider.overrideWithValue(true),
        currentStaffProvider.overrideWith((_) => Stream.value(_admin)),
        currentUserProvider.overrideWith((_) => Stream.value(AppUser(
              uid: 'uid-admin',
              email: 'robin.administrator@example.test',
              role: 'admin',
              createdAt: DateTime(2026),
            ))),
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
    );

    expect(find.text('Profile'), findsOneWidget);
    await _reveal(tester, find.text('robin.administrator@example.test'));
    expect(find.text('robin.administrator@example.test'), findsOneWidget);
    final signOut = find.widgetWithText(AdminDestructiveButton, 'Sign out');
    await _reveal(tester, find.text('Season report'));
    expect(find.text('Pre-delivery checklist'), findsOneWidget);
    await _reveal(tester, signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.text('Are you sure you want to sign out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('checklist items reorder by drag handle and open their options',
      (tester) async {
    final notifier = _ChecklistNotifier();
    await _pump(
      tester,
      const ChecklistManagementScreen(),
      overrides: [
        isAdminProvider.overrideWithValue(true),
        initializeChecklistProvider.overrideWith((_) async {}),
        checklistNotifierProvider.overrideWith((_) => notifier),
        checklistItemsProvider.overrideWith((_) => Stream.value([
              for (var i = 1; i <= 3; i++)
                ChecklistItem(
                  id: 'item-$i',
                  title: 'Item $i',
                  order: i,
                  isActive: i != 3,
                  createdAt: DateTime(2026),
                ),
            ])),
      ],
    );

    await _reveal(tester, find.text('Item 2'));
    expect(find.text('Disabled'), findsOneWidget);
    expect(
        find.widgetWithText(AppGlassPrimaryButton, 'Add item'), findsOneWidget);

    final handle = find.byIcon(HeroiconsOutline.bars3).first;
    final step = tester.getCenter(find.text('Item 2')).dy -
        tester.getCenter(find.text('Item 1')).dy;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    // 0.8 rows: the dragged item's end passes the middle of item 2.
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(0, step * 0.2));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(notifier.reordered, ['item-2', 'item-1', 'item-3']);

    await _reveal(tester, find.byType(AdminOptionsButton).first);
    await tester.tap(find.byType(AdminOptionsButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Disable'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff management floats add staff and opens member options',
      (tester) async {
    await _pump(
      tester,
      const StaffManagementScreen(),
      overrides: [
        staffListProvider.overrideWith((_) async => [_admin]),
        calendarMetadataProvider.overrideWith((_, __) async => null),
      ],
    );

    expect(find.text('Linked to user account'), findsOneWidget);
    await _reveal(tester, find.byType(AdminOptionsButton));
    await tester.tap(find.byType(AdminOptionsButton));
    await tester.pumpAndSettle();
    expect(find.text('Create invitation'), findsOneWidget);
    expect(find.text('Manage calendar'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppGlassPrimaryButton, 'Add staff'));
    await tester.pumpAndSettle();
    expect(find.text('Full name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('season export shows the ready report with share and new export',
      (tester) async {
    await _pump(
      tester,
      const SeasonExportScreen(),
      overrides: [
        seasonExportPreviewProvider
            .overrideWith((_, __) async => const SeasonExportPreview(
                  schoolCount: 12,
                  deliveryCount: 40,
                  staffCount: 6,
                  signedSummaryCount: 38,
                  timerEntryCount: 120,
                  earliestDate: null,
                  latestDate: null,
                )),
        seasonExportNotifierProvider.overrideWith((_) => _ExportNotifier(
            const SeasonExportState(filePath: '/tmp/report.xlsx'))),
      ],
    );

    await _reveal(tester, find.text('Report ready'));
    expect(find.text('Report ready'), findsOneWidget);
    expect(find.widgetWithText(AppPrimaryButton, 'Share'), findsOneWidget);
    expect(find.text('New export'), findsOneWidget);
    // The floating action only offers a new report while idle.
    expect(find.byType(AppGlassPrimaryButton), findsNothing);
    await tester.scrollUntilVisible(find.text('Timer entries'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('120'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ChecklistRepository implements ChecklistRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChecklistNotifier extends ChecklistNotifier {
  _ChecklistNotifier() : super(_ChecklistRepository());

  List<String>? reordered;

  @override
  Future<bool> reorderChecklistItems(List<ChecklistItem> items) async {
    reordered = [for (final item in items) item.id];
    return true;
  }
}

class _SeasonExportRepository implements SeasonExportRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ExportNotifier extends SeasonExportNotifier {
  _ExportNotifier(SeasonExportState initial)
      : super(_SeasonExportRepository()) {
    state = initial;
  }
}
