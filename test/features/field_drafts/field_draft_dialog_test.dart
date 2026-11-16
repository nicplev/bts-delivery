import 'dart:async';

import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/field_draft_providers.dart';
import 'package:bts_delivery_app/repositories/classroom_edit.dart';
import 'package:bts_delivery_app/services/offline/field_draft_store.dart';
import 'package:bts_delivery_app/services/result.dart';
import 'package:bts_delivery_app/widgets/field_draft_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = FieldDraftTarget(
  schoolId: 'school',
  deliveryId: 'monday',
  yearLevelId: 'year',
  classroomId: 'room',
  form: 'note',
);

void main() {
  testWidgets('a late input event survives acknowledgment of an older revision',
      (
    tester,
  ) async {
    final store = _Drafts();
    final acknowledgment = Completer<Result<ClassroomEditStatus>>();
    late FieldDraft submitted;
    await _pumpForm(tester, store, (draft) {
      submitted = draft;
      return acknowledgment.future;
    });
    await _open(tester);
    await tester.enterText(find.byType(TextFormField), 'First version');
    final field = tester.widget<TextField>(find.byType(TextField));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(submitted.values['content'], 'First version');

    // An input event queued just before the form disabled editing still arrives.
    field.controller!.text = 'Newer detail';
    field.onChanged!('Newer detail');
    acknowledgment.complete(const Result.success(ClassroomEditStatus.saved));
    await tester.pumpAndSettle();

    final kept = (await store.read(_target.keyFor('owner')))!;
    expect(kept.revision, isNot(submitted.revision));
    expect(kept.values['content'], 'Newer detail');
    expect(find.text('Add note'), findsOneWidget);
    expect(find.text('Newer detail'), findsOneWidget);
  });

  testWidgets(
      'dismissal persists the latest text and retry reuses its revision', (
    tester,
  ) async {
    final store = _Drafts();
    var canSave = false;
    final submissions = <FieldDraft>[];
    await _pumpForm(tester, store, (draft) async {
      submissions.add(draft);
      return canSave
          ? const Result.success(ClassroomEditStatus.pending)
          : const Result.failure('Couldn’t submit the note.');
    });
    await _open(tester);
    await tester.enterText(find.byType(TextFormField), 'Use the north door.');
    await tester.pump();
    expect(find.text('Saving draft…'), findsOneWidget);
    expect(await store.read(_target.keyFor('owner')), isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Add note'), findsNothing);
    final persisted = (await store.read(_target.keyFor('owner')))!;
    expect(persisted.values, {'content': 'Use the north door.'});

    await _open(tester);
    expect(find.text('Use the north door.'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t submit the note.'), findsOneWidget);
    expect(find.text('Use the north door.'), findsOneWidget);
    expect(submissions.single.revision, persisted.revision);

    canSave = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(submissions.last.revision, persisted.revision);
    expect(
        find.text('Note saved on this device · Sync pending'), findsOneWidget);
    expect(await store.read(_target.keyFor('owner')), isNull);
  });

  testWidgets(
      'a failed disk write keeps the form open and discard clears the draft', (
    tester,
  ) async {
    final store = _Drafts()..failWrites = true;
    var submitted = false;
    await _pumpForm(tester, store, (draft) async {
      submitted = true;
      return const Result.success(ClassroomEditStatus.saved);
    });
    await _open(tester);
    await tester.enterText(find.byType(TextFormField), 'Keep this text');
    await tester.pump(const Duration(milliseconds: 201));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t save the draft on this device. Retry.'),
        findsOneWidget);
    expect(find.text('Draft saved on this device'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Keep this text'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(submitted, isFalse);

    store.failWrites = false;
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await _open(tester);
    expect(find.text('Keep this text'), findsOneWidget);
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(await store.read(_target.keyFor('owner')), isNull);
    await _open(tester);
    expect(find.text('Keep this text'), findsNothing);
  });

  testWidgets('inactivity flushes a draft and large text fits above keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Drafts();
    await _pumpForm(
      tester,
      store,
      (draft) async => const Result.success(ClassroomEditStatus.saved),
      largeText: true,
    );
    await _open(tester);
    await tester.enterText(find.byType(TextFormField), 'Save before the timer');
    await tester.pump();
    expect(await store.read(_target.keyFor('owner')), isNull);

    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(
      (await store.read(_target.keyFor('owner')))?.values,
      {'content': 'Save before the timer'},
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'changing accounts hides the open draft and prevents submitting it', (
    tester,
  ) async {
    final users = StreamController<User?>();
    final store = _Drafts();
    var submitted = false;
    addTearDown(users.close);
    await _pumpForm(
      tester,
      store,
      (_) async {
        submitted = true;
        return const Result.success(ClassroomEditStatus.saved);
      },
      users: users.stream,
    );
    users.add(_User('owner'));
    await tester.pump();
    await _open(tester);
    await tester.enterText(find.byType(TextFormField), 'Private note');
    await tester.pump();
    users.add(_User('other'));
    await tester.pumpAndSettle();
    expect(find.text('Private note'), findsNothing);
    expect(find.text('This draft belongs to the previous account.'),
        findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect((await store.read(_target.keyFor('owner')))?.values['content'],
        'Private note');
    expect(await store.read(_target.keyFor('other')), isNull);
    expect(submitted, isFalse);
  });
}

Future<void> _pumpForm(
  WidgetTester tester,
  FieldDraftStore store,
  Future<Result<ClassroomEditStatus>> Function(FieldDraft draft) onSave, {
  bool largeText = false,
  Stream<User?>? users,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fieldDraftStoreProvider.overrideWith((_) async => store),
        authStateProvider
            .overrideWith((_) => users ?? Stream.value(_User('owner'))),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(largeText ? 1.8 : 1),
            viewInsets: EdgeInsets.only(bottom: largeText ? 265 : 0),
          ),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) {
            // Start the auth stream before the operator opens a form.
            ref.watch(authStateProvider);
            return Scaffold(
              body: FilledButton(
                onPressed: () => showFieldDraftDialog(
                  context: context,
                  ref: ref,
                  target: _target,
                  title: 'Add note',
                  savedLabel: 'Note',
                  inputs: [
                    FieldDraftInput(
                      id: 'content',
                      label: 'Note',
                      maxLines: 4,
                      validator: (value) =>
                          value.trim().isEmpty ? 'Enter a note.' : null,
                    ),
                  ],
                  onSave: onSave,
                ),
                child: const Text('Open note form'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open note form'));
  await tester.pumpAndSettle();
  expect(find.byType(TextFormField), findsOneWidget);
}

class _Drafts implements FieldDraftStore {
  final values = <String, FieldDraft>{};
  bool failWrites = false;

  @override
  Future<FieldDraft?> read(String key) async => values[key];

  @override
  Future<void> write(String key, FieldDraft draft) async {
    if (failWrites) throw StateError('disk write failed');
    values[key] = draft;
  }

  @override
  Future<void> remove(String key, {required String revision}) async {
    if (values[key]?.revision == revision) values.remove(key);
  }
}

class _User implements User {
  _User(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
