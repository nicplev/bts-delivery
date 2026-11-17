import 'package:bts_delivery_app/app/shell/app_shell.dart';
import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bts_delivery_app/widgets/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  shellTests();

  testWidgets('status ring speaks its state', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppStatusRing(status: AppCompletion.complete),
        AppStatusRing.fromCounts(done: 13, total: 24),
        AppStatusRing.fromCounts(done: 0, total: 12),
        const AppStatusRing(
            status: AppCompletion.partial,
            progress: 0.5,
            semanticLabel: '13 of 24 packs'),
      ],
    )));
    expect(find.bySemanticsLabel('Complete'), findsOneWidget);
    expect(find.bySemanticsLabel('Partial'), findsOneWidget);
    expect(find.bySemanticsLabel('Not started'), findsOneWidget);
    expect(find.bySemanticsLabel('13 of 24 packs'), findsOneWidget);
    expect(AppCompletion.fromCounts(24, 24), AppCompletion.complete);
    expect(AppCompletion.fromCounts(0, 0), AppCompletion.notStarted);
    semantics.dispose();
  });

  testWidgets('progress bar exposes label and value', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const SizedBox(
        width: 200,
        child: AppProgressBar(value: 0.54, semanticLabel: 'Packs recorded'))));
    expect(
      tester.getSemantics(find.byType(LinearProgressIndicator)),
      matchesSemantics(label: 'Packs recorded', value: '54%'),
    );
    semantics.dispose();
  });

  testWidgets('glass blurs normally and falls back to opaque in high contrast',
      (tester) async {
    const glass = AppGlass(child: SizedBox(width: 80, height: 44));
    await tester.pumpWidget(_app(glass));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const ValueKey('app-glass-opaque')), findsNothing);

    await tester
        .pumpWidget(_app(glass, theme: AppTheme.highContrastLightTheme));
    await tester.pumpAndSettle(); // theme change animates
    expect(find.byType(BackdropFilter), findsNothing);
    final box = tester
        .widget<DecoratedBox>(find.byKey(const ValueKey('app-glass-opaque')));
    final decoration = box.decoration as BoxDecoration;
    const colors = AppPalette(highContrast: true);
    expect(decoration.color, colors.surface);
    expect((decoration.border! as Border).top.color, colors.outline);
  });

  testWidgets('tab bar marks the selected tab and reports taps',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final tapped = <int>[];
    await tester.pumpWidget(_app(SizedBox(
      width: 358,
      child: AppGlassTabBar(
        items: const [
          AppTabItem(
              label: 'Deliveries',
              icon: AppIcons.deliveries,
              selectedIcon: AppIcons.deliveriesSolid),
          AppTabItem(
              label: 'Schools',
              icon: AppIcons.schools,
              selectedIcon: AppIcons.schoolsSolid),
          AppTabItem(
              label: 'Profile',
              icon: AppIcons.profile,
              selectedIcon: AppIcons.profileSolid),
        ],
        selectedIndex: 1,
        onSelected: tapped.add,
      ),
    )));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('app-tab-1'))),
      matchesSemantics(
        label: 'Schools',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('app-tab-0'))),
      matchesSemantics(
        label: 'Deliveries',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(find.byIcon(AppIcons.schoolsSolid), findsOneWidget);
    expect(find.byIcon(AppIcons.deliveries), findsOneWidget);
    expect(tester.getSize(find.byType(AppGlassTabBar)).height,
        AppTokens.tabBarHeight);
    await tester.tap(find.text('Profile'));
    expect(tapped, [2]);
    semantics.dispose();
  });

  testWidgets('year badge and filter use year colours and labels',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var selected = <SchoolYear>{SchoolYear.year1};
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              const AppYearBadge(label: 'Year 2'),
              const AppYearBadge(label: 'Art Specialist', size: 44),
              SizedBox(
                width: 200, // narrower than the row: it must scroll
                child: AppYearFilter(
                  selected: selected,
                  onToggle: (year) => setState(() {
                    selected = {...selected}..toggle(year);
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    final badges = find.byType(AppYearBadge);
    expect(find.descendant(of: badges.first, matching: find.text('2')),
        findsOneWidget);
    expect(find.descendant(of: badges.last, matching: find.text('A')),
        findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('year-filter-year1'))),
      matchesSemantics(
        label: 'Year 1',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(find.bySemanticsLabel('Prep'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('year-filter-prep')));
    await tester.pump();
    expect(selected, {SchoolYear.year1, SchoolYear.prep});
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('nav bar back pops through go_router', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/detail'),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/detail',
        builder: (_, __) => Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppNavBar(
            backLabel: 'Back to list',
            actions: [
              AppGlassIconButton(
                icon: AppIcons.more,
                semanticLabel: 'Options',
                onPressed: () {},
              ),
            ],
          ),
          body: ListView(
            children: const [AppLargeTitle(title: 'Detail', subtitle: 'Sub')],
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);
    expect(find.bySemanticsLabel('Options'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back to list'));
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('glass sheet shows title and closes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppGlassSheet<void>(
                context: context,
                title: 'Record packs',
                builder: (_) => const Text('Sheet body'),
              ),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Record packs'), findsOneWidget);
    expect(find.text('Sheet body'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsNothing);
  });

  testWidgets('floating action area reserves bottom padding', (tester) async {
    late EdgeInsets inner;
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: AppFloatingActionArea(
          action: AppGlassPrimaryButton(
            label: 'Record packs',
            onPressed: () => pressed = true,
          ),
          child: Builder(builder: (context) {
            inner = MediaQuery.paddingOf(context);
            return const SizedBox.expand();
          }),
        ),
      ),
    ));
    expect(
        inner.bottom, greaterThanOrEqualTo(AppTokens.primaryButtonHeight + 12));
    await tester.tap(find.text('Record packs'));
    expect(pressed, isTrue);
  });

  testWidgets('list rows are tappable and show detail and chevron',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(SizedBox(
      width: 358,
      child: AppGroupedList(
        separatorIndent: 57,
        children: [
          AppListRow(
            icon: AppIcons.consumables,
            title: 'Consumables',
            detail: '2 items',
            onTap: () => taps++,
          ),
          const AppListRow(title: 'Photos', subtitle: '1 photo'),
        ],
      ),
    )));
    expect(find.byIcon(AppIcons.chevron), findsOneWidget);
    expect(tester.getSize(find.byType(AppListRow).first).height,
        greaterThanOrEqualTo(52));
    await tester.tap(find.text('2 items'));
    expect(taps, 1);
  });
}

void shellTests() {
  testWidgets('shell tab bar navigates, marks selection and pads the body',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final paddings = <String, double>{};
    Widget page(String name) => Builder(builder: (context) {
          paddings[name] = MediaQuery.paddingOf(context).bottom;
          return Center(child: Text('$name body'));
        });
    final router = GoRouter(initialLocation: '/home', routes: [
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => page('home')),
          GoRoute(path: '/schools', builder: (_, __) => page('schools')),
          GoRoute(path: '/profile', builder: (_, __) => page('profile')),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [authStateProvider.overrideWith((_) => Stream.value(null))],
      child:
          MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('home body'), findsOneWidget);
    expect(paddings['home'], greaterThanOrEqualTo(AppTokens.tabBarHeight + 12));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('app-tab-0'))),
      matchesSemantics(
        label: 'Deliveries',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );

    await tester.tap(find.text('Schools'));
    await tester.pumpAndSettle();
    expect(find.text('schools body'), findsOneWidget);
    expect(
        router.routerDelegate.currentConfiguration.uri.toString(), '/schools');
    expect(find.byIcon(AppIcons.schoolsSolid), findsOneWidget);
    expect(find.byIcon(AppIcons.deliveries), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('profile body'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

extension<T> on Set<T> {
  void toggle(T value) {
    if (!remove(value)) add(value);
  }
}
