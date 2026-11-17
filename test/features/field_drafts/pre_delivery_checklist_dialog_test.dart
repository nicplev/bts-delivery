import 'dart:async';

import 'package:bts_delivery_app/models/delivery.dart';
import 'package:bts_delivery_app/models/offline/saved_edit.dart';
import 'package:bts_delivery_app/models/pre_delivery_checklist_item.dart';
import 'package:bts_delivery_app/models/pre_delivery_completion.dart';
import 'package:bts_delivery_app/providers/pre_delivery_checklist_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/providers/saved_edit_providers.dart';
import 'package:bts_delivery_app/repositories/auth_repository.dart';
import 'package:bts_delivery_app/repositories/classroom_edit.dart';
import 'package:bts_delivery_app/repositories/pre_delivery_checklist_repository.dart';
import 'package:bts_delivery_app/services/offline/connectivity_service.dart';
import 'package:bts_delivery_app/services/offline/saved_edit_recovery.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:bts_delivery_app/widgets/pre_delivery_checklist_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'checklist opens before data and distinguishes failure from a queued save',
      (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final items = StreamController<List<PreDeliveryChecklistItem>>();
      final completions = StreamController<List<PreDeliveryCompletion>>();
      addTearDown(items.close);
      addTearDown(completions.close);
      final recovery = _Recovery();
      final today = DateTime(2026);
      final delivery = Delivery(
        id: 'first',
        schoolId: 'school',
        schoolName: 'North Campus',
        date: today,
        createdAt: today,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_Auth()),
          savedEditRecoveryProvider.overrideWithValue(recovery),
          preDeliveryChecklistRepositoryProvider
              .overrideWithValue(_Checklist()),
          activePreDeliveryChecklistItemsProvider
              .overrideWith((_) => items.stream),
          deliveryCompletionsProvider
              .overrideWith((_, __) => completions.stream),
          connectivityStatusProvider
              .overrideWith((_) => Stream.value(ConnectivityStatus.offline)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
                builder: (context) => FilledButton(
                      onPressed: () => showPreDeliveryChecklistDialog(
                          context: context, delivery: delivery),
                      child: const Text('Open checklist'),
                    )),
          ),
        ),
      ));
      await tester.tap(find.text('Open checklist'));
      await tester.pumpAndSettle();
      expect(find.text('Checking saved checklist items…'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      items.add([
        PreDeliveryChecklistItem(
            id: 'gate',
            title: 'Confirm the gate access',
            order: 0,
            createdAt: today),
      ]);
      completions.add([]);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
          find.text('Couldn’t save your edit on this device.'), findsOneWidget);
      expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isFalse);

      recovery.fail = false;
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(find.text('Checklist change saved on this device · Sync pending'),
          findsOneWidget);
      expect(recovery.attempts.last.deliveryId, 'first');
      expect(recovery.attempts.last.itemId, 'gate');
      completions.add(const [
        PreDeliveryCompletion(itemId: 'gate', isCompleted: true),
      ]);
      await tester.pumpAndSettle();
      expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isTrue);
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}

class _Recovery implements SavedEditRecovery {
  bool fail = true;
  final attempts = <EditIntent>[];

  @override
  Future<Result<ClassroomEditReceipt>> save(EditIntent intent) async {
    attempts.add(intent);
    if (fail) {
      return const Result.failure('Couldn’t save your edit on this device.');
    }
    return Result.success((
      status: ClassroomEditStatus.pending,
      acknowledgment: Future.value(const Result.success(null)),
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Checklist implements PreDeliveryChecklistRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthRepository {
  @override
  User? get currentUser => _User();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  @override
  String get uid => 'driver';

  @override
  String? get email => 'driver@example.test';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
