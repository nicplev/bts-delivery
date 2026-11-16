import 'package:bts_delivery_app/models/offline/saved_edit.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/saved_edit_providers.dart';
import 'package:bts_delivery_app/services/offline/saved_edit_recovery.dart';
import 'package:bts_delivery_app/services/offline/saved_edit_store.dart';
import 'package:bts_delivery_app/widgets/saved_edits_review.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('open classroom closes both reviews and preserves the saved edit',
      (tester) async {
    final intent = EditIntent(
      id: '00000000-0000-4000-8000-000000000001',
      ownerUid: 'driver',
      schoolId: 'school',
      deliveryId: 'visit',
      yearLevelId: 'year',
      classroomId: 'room',
      kind: SavedEditKind.classroomName,
      capturedAt: DateTime.utc(2026, 11, 16),
      values: {'name': 'Room B'},
      updatedBy: 'Driver',
    );
    final edits = [SavedEdit(intent, SavedEditState.review)];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: SavedEditsBanner()),
        ),
        GoRoute(
          path:
              '/deliveries/:delivery/schools/:school/year/:year/classrooms/:room',
          builder: (_, state) => Scaffold(
            body: Text('Classroom in ${state.pathParameters['delivery']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(_Driver())),
        savedEditsProvider.overrideWith((_) => Stream.value(edits)),
        savedEditRecoveryProvider.overrideWithValue(SavedEditRecovery(
          store: HiveSavedEditStore(),
          transport: _ServerRoom(),
          currentUid: () => 'driver',
        )),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classroom name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open classroom'));
    await tester.pumpAndSettle();

    expect(find.text('Saved edits'), findsNothing);
    expect(find.text('Your saved values'), findsNothing);
    expect(find.text('Classroom in visit'), findsOneWidget);
    expect(edits.single.intent.id, intent.id);
  });
}

class _Driver implements User {
  @override
  String get uid => 'driver';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ServerRoom implements EditTransport {
  @override
  Future<ServerEditValues> readServer(EditIntent intent) async =>
      ServerEditValues(
        exists: true,
        hasPendingWrites: false,
        fields: const {'name': 'Room A'},
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
