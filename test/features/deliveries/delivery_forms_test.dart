import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/school.dart';
import 'package:bts_delivery_app/providers/schools_providers.dart';
import 'package:bts_delivery_app/screens/forms/add_edit_delivery_screen.dart';
import 'package:bts_delivery_app/screens/forms/bulk_import_screen.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: home,
      ),
    );

void _narrowScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('floating save stays above the keyboard and validates the school',
      (tester) async {
    _narrowScreen(tester);
    await tester.pumpWidget(_app(
      const AddEditDeliveryScreen(),
      overrides: [
        schoolsProvider.overrideWith((_) => Stream.value([
              School(
                id: 'school',
                name: 'Oakfield Primary',
                address: '',
                createdAt: DateTime(2026),
              ),
            ])),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Add delivery'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final save = find.text('Save delivery');
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(save).dy, lessThan(640 - 260));

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Please select a school'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('classroom import enables its floating action for valid CSV',
      (tester) async {
    _narrowScreen(tester);
    await tester.pumpWidget(_app(const BulkImportScreen(
      schoolId: 'school',
      schoolName: 'Oakfield Primary',
    )));
    await tester.pumpAndSettle();

    AppGlassPrimaryButton action() => tester
        .widget<AppGlassPrimaryButton>(find.byType(AppGlassPrimaryButton));
    expect(action().label, 'Import data');
    expect(action().onPressed, isNull);

    final paste = find.text('Paste template');
    await tester.scrollUntilVisible(paste, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(paste);
    await tester.pumpAndSettle();
    expect(action().onPressed, isNotNull);
    expect(find.text('Import data').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
