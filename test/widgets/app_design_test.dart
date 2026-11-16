import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the original brand colors and readable supporting tones', () {
    expect(AppTone.green.accent, const Color(0xFF2BB673));
    expect(AppTone.blue.accent, const Color(0xFF00AEEF));
    expect(AppTone.pink.accent, const Color(0xFFEC008C));
    expect(AppTone.yellow.accent, const Color(0xFFF9ED32));

    final colors = AppTheme.lightTheme.colorScheme;
    expect(
        _contrast(colors.primary, colors.onPrimary), greaterThanOrEqualTo(4.5));
    expect(_contrast(colors.secondary, colors.onSecondary),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(colors.tertiary, colors.onTertiary),
        greaterThanOrEqualTo(4.5));
    for (final tone in AppTone.values) {
      expect(_contrast(tone.tint, tone.ink), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('section action and status pills fit narrow large-text layouts',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pressed = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.8)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(AppTokens.gutter),
          children: [
            AppSectionHeading(
              title: 'Classroom records',
              trailing: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                onPressed: () => pressed = true,
                label: const Text('Add Year Level'),
              ),
            ),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppStatusPill(
                    label: 'Offline',
                    icon: Icons.cloud_off,
                    tone: AppTone.yellow),
                AppStatusPill(
                    label: 'Pending changes need review',
                    icon: Icons.edit_outlined,
                    tone: AppTone.pink),
              ],
            ),
          ],
        ),
      ),
    ));
    await tester.tap(find.text('Add Year Level'));
    expect(pressed, isTrue);
    expect(find.text('Pending changes need review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

double _contrast(Color surface, Color ink) {
  final a = surface.computeLuminance();
  final b = ink.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}
