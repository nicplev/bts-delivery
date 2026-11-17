import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/deliveries_providers.dart';
import 'package:bts_delivery_app/providers/schools_providers.dart';
import 'package:bts_delivery_app/screens/admin/school_staff_allocation_screen.dart';
import 'package:bts_delivery_app/screens/forms/add_edit_delivery_screen.dart';
import 'package:bts_delivery_app/screens/forms/schools_bulk_import_screen.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _school = School(
  id: 'school',
  name: 'North and South Campus Community Primary School',
  address:
      '101 Long Campus Road, Reception at the south entrance, behind the hall. '
      'Deliveries check in at the accessible gate on the western service road.',
  createdAt: DateTime(2026),
);

Widget _app(Widget home) => MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.8)),
        child: child!,
      ),
      home: home,
    );

void main() {
  testWidgets('staff selection remains reachable below a long school header',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        staffListProvider.overrideWith((_) async => [
              Staff(
                id: 'driver',
                name: 'Alex Delivery Coordinator',
                role: 'manager',
                assignedSchoolIds: const ['another-school'],
                createdAt: DateTime(2026),
              ),
            ]),
      ],
      child: _app(SchoolStaffAllocationScreen(school: _school)),
    ));
    await tester.pumpAndSettle();
    final staff = find.byType(CheckboxListTile);
    await tester.scrollUntilVisible(staff, 90);
    await tester.pumpAndSettle();
    await tester.tap(staff);
    await tester.pumpAndSettle();

    expect(tester.widget<CheckboxListTile>(staff).value, isTrue);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'delivery school selection and save stay reachable with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        schoolsProvider.overrideWith((_) => Stream.value([_school]))
      ],
      child: _app(const AddEditDeliveryScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<School>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_school.name).last);
    await tester.pumpAndSettle();
    final save = find.text('Save delivery');
    await tester.scrollUntilVisible(save, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'school import keeps its primary action reachable with the keyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        ProviderScope(child: _app(const SchoolsBulkImportScreen())));
    await tester.pumpAndSettle();

    final input = find.byType(TextField);
    await tester.scrollUntilVisible(input, 110,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(input, 'School Name\nExample Primary');
    tester.view.viewInsets = const FakeViewPadding(bottom: 210);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(AppGlassPrimaryButton, 'Import schools');
    await tester.scrollUntilVisible(submit, 140,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
