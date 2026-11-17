import 'package:bts_delivery_app/app/app.dart';
import 'package:bts_delivery_app/services/offline/offline_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _palettes = [
  AppPalette(),
  AppPalette(dark: true),
  AppPalette(highContrast: true),
  AppPalette(dark: true, highContrast: true),
];

void main() {
  test('themes are neutral and readable in all four variants', () {
    for (final theme in [
      AppTheme.lightTheme,
      AppTheme.darkTheme,
      AppTheme.highContrastLightTheme,
      AppTheme.highContrastDarkTheme,
    ]) {
      final scheme = theme.colorScheme;
      final colors = theme.extension<AppPalette>()!;
      final reason =
          'dark=${colors.dark}, high contrast=${colors.highContrast}';
      final textMinimum = colors.highContrast ? 7.0 : 4.5;
      expect(theme.textTheme.bodyMedium?.fontSize, 17);
      expect(theme.textTheme.displayMedium?.fontSize, 34);
      expect(theme.brightness, colors.brightness);
      expect(theme.scaffoldBackgroundColor, colors.canvas);

      // Actions are ink; nothing in the scheme is a saturated hue.
      expect(scheme.primary, colors.action, reason: reason);
      expect(scheme.onPrimary, colors.onAction, reason: reason);
      for (final color in [
        scheme.primary,
        scheme.secondary,
        scheme.tertiary,
        scheme.primaryContainer,
        scheme.secondaryContainer,
        scheme.surface,
        colors.canvas,
        colors.surfaceQuiet,
        colors.ink,
        colors.muted,
        colors.outline,
      ]) {
        expect(_isNeutral(color), isTrue, reason: '$color, $reason');
      }

      expect(_contrast(colors.action, colors.onAction),
          greaterThanOrEqualTo(textMinimum),
          reason: reason);
      expect(_contrast(scheme.secondary, scheme.onSecondary),
          greaterThanOrEqualTo(4.5),
          reason: reason);
      expect(_contrast(scheme.tertiary, scheme.onTertiary),
          greaterThanOrEqualTo(4.5),
          reason: reason);
      expect(_contrast(scheme.error, scheme.onError), greaterThanOrEqualTo(4.5),
          reason: reason);
      for (final background in [
        colors.canvas,
        colors.surface,
        colors.surfaceQuiet
      ]) {
        expect(_contrast(background, colors.ink),
            greaterThanOrEqualTo(textMinimum),
            reason: reason);
        expect(_contrast(background, colors.muted),
            greaterThanOrEqualTo(textMinimum),
            reason: reason);
      }
      expect(_contrast(colors.warningTint, colors.warningInk),
          greaterThanOrEqualTo(textMinimum),
          reason: reason);
      for (final tone in AppTone.values) {
        expect(
          _contrast(tone.tintOn(colors), tone.inkOn(colors)),
          greaterThanOrEqualTo(textMinimum),
          reason: '$tone, $reason',
        );
      }
      if (colors.highContrast) {
        expect(
            _contrast(colors.outline, colors.surface), greaterThanOrEqualTo(3));
      }
      // Cards have no border in normal contrast, an outline in high contrast.
      final cardSide = (theme.cardTheme.shape! as RoundedRectangleBorder).side;
      expect(cardSide == BorderSide.none, !colors.highContrast);
    }
    expect(AppTheme.lightTheme.scaffoldBackgroundColor,
        isNot(AppTheme.darkTheme.scaffoldBackgroundColor));
  });

  test('tones are neutral grey or warning amber only', () {
    expect(AppTone.values, [AppTone.neutral, AppTone.warning]);
    for (final colors in _palettes) {
      expect(AppTone.neutral.tintOn(colors), colors.surfaceQuiet);
      expect(AppTone.neutral.inkOn(colors), colors.ink);
      expect(AppTone.warning.tintOn(colors), colors.warningTint);
      expect(AppTone.warning.inkOn(colors), colors.warningInk);
    }
  });

  test('year levels map to the seven company colours with readable labels', () {
    const expected = {
      SchoolYear.prep: Color(0xFF1A1A1A),
      SchoolYear.year1: Color(0xFFD62828),
      SchoolYear.year2: Color(0xFF00AEEF),
      SchoolYear.year3: Color(0xFF2BB673),
      SchoolYear.year4: Color(0xFF7B3FC4),
      SchoolYear.year5: Color(0xFFF9ED32),
      SchoolYear.year6: Color(0xFFF58220),
    };
    for (final colors in _palettes) {
      for (final year in SchoolYear.values) {
        final style = YearLevelColors.styleFor(year, colors);
        expect(style.fill, expected[year]);
        expect(style.isYear, isTrue);
        expect(style.shortLabel, year.shortLabel);
        expect(_contrast(style.fill, style.onFill), greaterThanOrEqualTo(4.5),
            reason: '$year');
        expect(style.needsBorder, year == SchoolYear.prep && colors.dark);
      }
      final neutral = YearLevelColors.styleForLabel('Specialist', colors);
      expect(neutral.isYear, isFalse);
      expect(neutral.fill, colors.surfaceQuiet);
      expect(neutral.onFill, colors.ink);
      expect(neutral.shortLabel, 'S');
    }
    expect(SchoolYear.values.map((y) => y.shortLabel),
        ['P', '1', '2', '3', '4', '5', '6']);
    expect(SchoolYear.year3.label, 'Year 3');
  });

  test('year labels parse only the seven year levels', () {
    const cases = <String, SchoolYear?>{
      'Prep': SchoolYear.prep,
      'prep A': SchoolYear.prep,
      'Foundation': SchoolYear.prep,
      'Year 1': SchoolYear.year1,
      'YEAR 2 – Room B': SchoolYear.year2,
      'Yr 3': SchoolYear.year3,
      'Yr.4': SchoolYear.year4,
      'Grade 5': SchoolYear.year5,
      'Y6': SchoolYear.year6,
      'Year 7': null,
      'Year 10': null,
      'Year 1/2': null,
      'Year 3 & 4': null,
      'Prep/1 Composite': null,
      'Composite': null,
      'Specialist': null,
      'Art Specialist': null,
      'Room 1A': null,
      '': null,
    };
    cases.forEach((label, year) {
      expect(SchoolYear.parse(label), year, reason: label);
    });
    expect(SchoolYear.parse(null), isNull);
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
                icon: const Icon(AppIcons.add),
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
                    icon: AppIcons.offline,
                    tone: AppTone.warning),
                AppStatusPill(label: 'Pending changes need review'),
              ],
            ),
            const AppWarningNotice(
                message: '23 packs outstanding in 2 classrooms'),
          ],
        ),
      ),
    ));
    final button = find.widgetWithText(OutlinedButton, 'Add Year Level');
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    final offline = tester.widget<Text>(find.text('Offline'));
    expect(offline.style?.color,
        const AppPalette(dark: true, highContrast: true).warningInk);
    await tester.tap(button);
    expect(pressed, isTrue);
    expect(find.text('Pending changes need review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// True when the colour has (almost) no saturation.
bool _isNeutral(Color color) {
  final hsl = HSLColor.fromColor(color.withValues(alpha: 1));
  return hsl.saturation < 0.12 || hsl.lightness < 0.06 || hsl.lightness > 0.93;
}

double _contrast(Color surface, Color ink) {
  final a = surface.computeLuminance();
  final b = ink.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}
