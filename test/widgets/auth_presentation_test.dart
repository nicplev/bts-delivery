import 'package:bts_delivery_app/app/theme/app_theme.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/repositories/auth_repository.dart';
import 'package:bts_delivery_app/screens/auth/login_screen.dart';
import 'package:bts_delivery_app/screens/auth/staff_link_screen.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sign-in and staff linking stay usable above a narrow keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 230);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repository = _AuthFixture();

    Widget app(Widget screen) => ProviderScope(
          key: ValueKey(screen.runtimeType),
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            currentStaffProvider.overrideWith((_) => Stream.value(null)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.7),
              ),
              child: child!,
            ),
            home: screen,
          ),
        );

    await tester.pumpWidget(app(const LoginScreen()));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'driver@example.test');
    await tester.enterText(fields.at(1), 'fixture-password');
    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(repository.email, 'driver@example.test');
    expect(find.text('Sign-in fixture error'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(app(const StaffLinkScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test-invite');
    final link = find.widgetWithText(FilledButton, 'Link account');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(repository.invite, 'test-invite');
    expect(find.text('Link fixture error'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _AuthFixture implements AuthRepository {
  String? email;
  String? invite;

  @override
  Future<Result<User>> signInWithEmailAndPassword(
      String email, String password) async {
    this.email = email;
    return const Result.failure('Sign-in fixture error');
  }

  @override
  Future<Result<Staff>> linkToStaff(String code) async {
    invite = code;
    return const Result.failure('Link fixture error');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
