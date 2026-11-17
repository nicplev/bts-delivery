import 'package:bts_delivery_app/app/app.dart';
import 'package:bts_delivery_app/services/offline/offline_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    for (final theme in [
      AppTheme.lightTheme,
      AppTheme.darkTheme,
      AppTheme.highContrastLightTheme,
      AppTheme.highContrastDarkTheme,
    ]) {
      final scheme = theme.colorScheme;
      final colors = theme.extension<AppPalette>()!;
      expect(theme.textTheme.bodyMedium?.fontSize, 17);
      expect(theme.brightness, colors.brightness);
      expect(theme.scaffoldBackgroundColor, colors.canvas);
      expect(_contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(scheme.secondary, scheme.onSecondary),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(scheme.tertiary, scheme.onTertiary),
          greaterThanOrEqualTo(4.5));
      expect(
          _contrast(scheme.error, scheme.onError), greaterThanOrEqualTo(4.5));
      final textMinimum = colors.highContrast ? 7.0 : 4.5;
      expect(_contrast(colors.surfaceQuiet, colors.muted),
          greaterThanOrEqualTo(textMinimum));
      for (final tone in AppTone.values) {
        expect(
          _contrast(tone.tintOn(colors), tone.inkOn(colors)),
          greaterThanOrEqualTo(textMinimum),
          reason:
              '$tone, dark=${colors.dark}, high contrast=${colors.highContrast}',
        );
      }
      if (colors.highContrast) {
        expect(
            _contrast(colors.outline, colors.surface), greaterThanOrEqualTo(3));
      }
    }
    expect(AppTheme.lightTheme.scaffoldBackgroundColor,
        isNot(AppTheme.darkTheme.scaffoldBackgroundColor));
  });

  testWidgets('startup follows system dark and high contrast settings',
      (tester) async {
    final platform = tester.platformDispatcher;
    platform.platformBrightnessTestValue = Brightness.dark;
    platform.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        highContrast: true, disableAnimations: true);
    addTearDown(platform.clearPlatformBrightnessTestValue);
    addTearDown(platform.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        offlineStorageInitProvider.overrideWith(
          (_) => Future<void>.error(StateError('storage unavailable')),
        ),
      ],
      child: const BTSDeliveryApp(),
    ));
    final loading = find.text('Initializing app...');
    expect(loading, findsOneWidget);
    expect(AppPalette.of(tester.element(loading)).dark, isTrue);
    expect(AppPalette.of(tester.element(loading)).highContrast, isTrue);

    await tester.pumpAndSettle();
    final error = find.textContaining('Initialization failed');
    expect(error, findsOneWidget);
    expect(AppPalette.of(tester.element(error)).dark, isTrue);
    expect(AppPalette.of(tester.element(error)).highContrast, isTrue);
    expect(find.text('Retry').hitTestable(), findsOneWidget);
  });

  testWidgets('section action and status pills fit narrow large-text layouts',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pressed = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.highContrastDarkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
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
    final button = find.widgetWithText(OutlinedButton, 'Add Year Level');
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    final offline = tester.widget<Text>(find.text('Offline'));
    expect(offline.style?.color,
        AppTone.yellow.inkOn(const AppPalette(dark: true, highContrast: true)));
    await tester.tap(button);
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
