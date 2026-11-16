import 'dart:async';
import 'dart:io';

import 'package:bts_delivery_app/models/offline/saved_edit.dart';
import 'package:bts_delivery_app/repositories/classroom_edit.dart';
import 'package:bts_delivery_app/services/offline/saved_edit_recovery.dart';
import 'package:bts_delivery_app/services/offline/saved_edit_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late _TestTransport remote;
  late HiveSavedEditStore store;
  late String? signedIn;

  SavedEditRecovery recovery({SavedEditStore? editStore}) => SavedEditRecovery(
        store: editStore ?? store,
        transport: remote,
        currentUid: () => signedIn,
        localWait: const Duration(milliseconds: 25),
        serverWait: const Duration(milliseconds: 100),
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bts-edits-test');
    Hive.init(directory.path);
    store = HiveSavedEditStore();
    remote = _TestTransport();
    signedIn = 'driver-a';
  });

  tearDown(() async {
    await remote.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('failed local admission does not reach Firestore', () async {
    final worker = recovery(editStore: _FailingStore());
    final result = await worker.save(_name('My room'));
    expect(result.isFailure, isTrue);
    expect(result.errorOrNull, contains('on the device'));
    expect(remote.submitted, isEmpty);
  });

  test('soft disk timeout does not let the same draft bypass durable admission',
      () async {
    final disk = _TimedOutStore();
    final worker = recovery(editStore: disk);
    final edit = _note('Keep this draft');
    expect((await worker.save(edit)).isFailure, isTrue);
    expect((await worker.save(edit)).isFailure, isTrue);
    expect(disk.puts, 1);
    expect(remote.submitted, isEmpty);
    final outstandingWrite = disk.firstWrite;
    disk.release.completeError(StateError('Disk failed'));
    await expectLater(outstandingWrite, throwsStateError);

    final retry = await worker.save(edit);
    expect(retry.dataOrNull!.status, ClassroomEditStatus.saved);
    expect(remote.submitted, [edit.id]);
  });

  test(
      'restart retains uncertain intent, never replays, and compares newer values',
      () async {
    final edit = _name('My room');
    remote.acknowledgment = Completer<void>();
    remote.rows[edit.path] = {'name': 'First room', 'actualPacksDelivered': 6};
    final original = recovery();
    expect((await original.save(edit)).dataOrNull!.status,
        ClassroomEditStatus.unconfirmed);
    expect(remote.submitted, [edit.id]);

    original.dispose();
    await Hive.close();
    Hive.init(directory.path);
    store = HiveSavedEditStore();
    final restarted = recovery();
    remote.rows[edit.path] = {
      'name': 'Teammate room',
      'actualPacksDelivered': 7
    };
    await restarted.reconcile('driver-a');
    final saved = (await store.pending('driver-a')).single;
    expect(saved.state, SavedEditState.review);
    expect(saved.intent.values, {'name': 'My room'});
    expect(remote.rows[edit.path]!['name'], 'Teammate room');
    expect(remote.submitted, [edit.id]);
    expect(remote.retried, isEmpty);

    final reviewed = await restarted.compare(saved.intent);
    expect(reviewed.current!.fields, {'name': 'Teammate room'});
    remote.rows[edit.path]!['name'] = 'Another change';
    expect((await restarted.retry(saved.intent, reviewed)).isFailure, isTrue);
    expect(remote.retried, isEmpty);

    final fresh = await restarted.compare(saved.intent);
    expect((await restarted.retry(saved.intent, fresh)).isSuccess, isTrue);
    expect(
        remote.rows[edit.path], {'name': 'My room', 'actualPacksDelivered': 7});
    expect(await store.pending('driver-a'), isEmpty);
  });

  test('native pending overlay cannot prove acknowledgment or be cleared',
      () async {
    final edit = _name('My room');
    await store.put(SavedEdit(edit, SavedEditState.queued));
    remote.rows[edit.path] = edit.fields;
    remote.pendingPaths.add(edit.path);

    final worker = recovery();
    await worker.reconcile('driver-a');
    expect(
        (await store.pending('driver-a')).single.state, SavedEditState.queued);
    final pending = await worker.compare(edit);
    expect(pending.canResolve, isFalse);
    expect((await worker.clear(edit, pending)).isFailure, isTrue);

    final matchedRecord = store.watch('driver-a').firstWhere((edits) =>
        edits.length == 1 && edits.single.state == SavedEditState.matched);
    await remote.settle(edit);
    await matchedRecord.timeout(const Duration(seconds: 1));
    final matched = await worker.compare(edit);
    expect(matched.message, contains('server values match'));
    expect(matched.canRetry, isFalse);
    expect((await worker.clear(edit, matched)).isSuccess, isTrue);
    expect(await store.pending('driver-a'), isEmpty);
  });

  test('same draft ID creates one note across duplicate saves and restart',
      () async {
    final note = _note('Deliver to reception');
    final worker = recovery();
    remote.acknowledgment = Completer<void>();
    final first = worker.save(note);
    final repeated = worker.save(_note('Deliver to reception'));
    expect((await first).dataOrNull!.status, ClassroomEditStatus.unconfirmed);
    expect(
        (await repeated).dataOrNull!.status, ClassroomEditStatus.unconfirmed);
    expect(remote.submitted, [note.id]);

    remote.acknowledgment!.complete();
    await (await first).dataOrNull!.acknowledgment;
    expect(remote.rows.keys, [note.path]);
    expect(await store.pending('driver-a'), isEmpty);

    worker.dispose();
    await Hive.close();
    Hive.init(directory.path);
    store = HiveSavedEditStore();
    final restarted = recovery();
    final duplicate = await restarted.save(_note('Deliver to reception'));
    expect(duplicate.dataOrNull!.status, ClassroomEditStatus.saved);
    expect((await restarted.save(_note('Different value'))).isFailure, isTrue);
    expect(remote.submitted, [note.id]);
    expect(remote.rows[note.path]!['createdAt'],
        note.capturedAt.microsecondsSinceEpoch);
  });

  test('stable create collision after restart cannot overwrite another note',
      () async {
    final note = _note('Deliver to reception');
    await store.put(SavedEdit(note, SavedEditState.review));
    remote.rows[note.path] = {
      'content': 'Another entry',
      'author': null,
      'createdAt': note.capturedAt.microsecondsSinceEpoch,
    };
    final worker = recovery();
    final comparison = await worker.compare(note);
    expect(comparison.canResolve, isTrue);
    expect(comparison.canRetry, isFalse);
    expect((await worker.retry(note, comparison)).isFailure, isTrue);
    expect(remote.rows[note.path]!['content'], 'Another entry');
  });

  test(
      'native acknowledgment settles the right intent after two edits to one classroom',
      () async {
    final rename = _name('Room B');
    final completion = EditIntent(
      id: '00000000-0000-4000-8000-000000000003',
      ownerUid: rename.ownerUid,
      schoolId: rename.schoolId,
      deliveryId: rename.deliveryId,
      yearLevelId: rename.yearLevelId,
      classroomId: rename.classroomId,
      kind: SavedEditKind.classroomStatus,
      capturedAt: DateTime.utc(2026, 11, 16),
      values: {'completionStatus': 'incomplete', 'actualPacksDelivered': 4},
      updatedBy: 'Driver',
    );
    final firstAck = Completer<void>();
    remote.acknowledgment = firstAck;
    remote.emitPending = true;
    final worker = recovery();
    final first = (await worker.save(rename)).dataOrNull!;
    expect(first.status, ClassroomEditStatus.pending);
    final secondAck = Completer<void>();
    remote.acknowledgment = secondAck;
    final second = (await worker.save(completion)).dataOrNull!;
    expect(second.status, ClassroomEditStatus.pending);

    firstAck.complete();
    await first.acknowledgment;
    expect((await store.pending('driver-a')).single.intent.id, completion.id);
    final pending = await worker.compare(completion);
    expect(pending.canResolve, isFalse);
    secondAck.complete();
    await second.acknowledgment;
    expect(await store.pending('driver-a'), isEmpty);
    expect(remote.rows[rename.path], {
      'name': 'Room B',
      'completionStatus': 'incomplete',
      'actualPacksDelivered': 4,
    });
  });

  test(
      'storage completion after account change leaves first account work private',
      () async {
    final disk = _DelayedStore();
    final worker = recovery(editStore: disk);
    final edit = _name('Private first account edit');
    final saving = worker.save(edit);
    await disk.started.future;
    signedIn = 'driver-b';
    worker.authenticationChanged();
    disk.continueWrite.complete();
    expect((await saving).dataOrNull!.status, ClassroomEditStatus.unconfirmed);
    expect(remote.submitted, isEmpty);
    expect(await disk.pending('driver-b'), isEmpty);
    expect((await disk.pending('driver-a')).single.intent.values, edit.values);

    signedIn = 'driver-a';
    worker.authenticationChanged();
    remote.rows[edit.path] = {'name': 'Existing room'};
    final reviewed = await worker.compare(edit);
    signedIn = 'driver-b';
    worker.authenticationChanged();
    signedIn = 'driver-a';
    worker.authenticationChanged();
    expect((await worker.retry(edit, reviewed)).isFailure, isTrue);
    expect(remote.retried, isEmpty);
  });

  test(
      'offline note deletion remains reviewable and cannot remove newer content silently',
      () async {
    final note = _note('Initial note');
    final deletion = EditIntent(
      id: '00000000-0000-4000-8000-000000000004',
      ownerUid: note.ownerUid,
      schoolId: note.schoolId,
      deliveryId: note.deliveryId,
      yearLevelId: note.yearLevelId,
      classroomId: note.classroomId,
      itemId: note.id,
      kind: SavedEditKind.noteDelete,
      capturedAt: DateTime.utc(2026, 11, 16),
      values: note.fields,
      updatedBy: 'Driver',
    );
    final worker = recovery();
    remote.rows[note.path] = {...note.fields, 'content': 'Teammate newer note'};
    remote.online = false;
    final saved = (await worker.save(deletion)).dataOrNull!;
    expect(saved.status, ClassroomEditStatus.unconfirmed);
    await saved.acknowledgment;
    expect(remote.submitted, isEmpty);
    expect(remote.retried, isEmpty);

    remote.online = true;
    await worker.reconcile('driver-a');
    expect(remote.rows[note.path]!['content'], 'Teammate newer note');
    final review = await worker.compare(deletion);
    expect(review.current!.fields['content'], 'Teammate newer note');
    expect((await worker.retry(deletion, review)).isSuccess, isTrue);
    expect(remote.rows[note.path], isNull);
  });
}

EditIntent _name(String name) => EditIntent(
      id: '00000000-0000-4000-8000-000000000001',
      ownerUid: 'driver-a',
      schoolId: 'school',
      deliveryId: 'visit',
      yearLevelId: 'year',
      classroomId: 'room',
      kind: SavedEditKind.classroomName,
      capturedAt: DateTime.utc(2026, 11, 16),
      values: {'name': name},
      updatedBy: 'Driver',
    );

EditIntent _note(String content) => EditIntent(
      id: '00000000-0000-4000-8000-000000000002',
      rememberId: true,
      ownerUid: 'driver-a',
      schoolId: 'school',
      deliveryId: 'visit',
      yearLevelId: 'year',
      classroomId: 'room',
      kind: SavedEditKind.noteCreate,
      capturedAt: DateTime.now().toUtc(),
      values: {'content': content, 'author': 'Driver'},
      updatedBy: 'Driver',
    );

class _TestTransport implements EditTransport {
  final rows = <String, Map<String, Object?>>{};
  final pendingPaths = <String>{};
  final submitted = <String>[];
  final retried = <String>[];
  final _pending = StreamController<String>.broadcast(sync: true);
  final _settled = StreamController<(String, ServerEditValues)>.broadcast();
  bool emitPending = false;
  bool online = true;
  Completer<void>? acknowledgment;

  Future<void> close() async {
    await _pending.close();
    await _settled.close();
  }

  Future<void> settle(EditIntent intent) async {
    pendingPaths.remove(intent.path);
    _settled.add((intent.path, await readServer(intent)));
  }

  @override
  Stream<ServerEditValues> watchSettled(EditIntent intent) => _settled.stream
      .where((entry) => entry.$1 == intent.path)
      .map((entry) => entry.$2);

  @override
  Stream<bool> watchPending(EditIntent intent) =>
      _pending.stream.map((id) => id == intent.id);

  @override
  Future<void> submit(EditIntent intent, void Function() requireOwner) async {
    requireOwner();
    submitted.add(intent.id);
    if (emitPending) _pending.add(intent.id);
    await acknowledgment?.future;
    _apply(intent);
  }

  @override
  Future<ServerEditValues> readServer(EditIntent intent) async {
    if (!online) throw StateError('Offline');
    final document = rows[intent.path];
    return ServerEditValues(
      exists: document != null,
      hasPendingWrites: pendingPaths.contains(intent.path),
      fields: {
        for (final field in intent.fields.keys)
          if (document?.containsKey(field) ?? false) field: document![field],
      },
    );
  }

  @override
  Future<void> retry(
    EditIntent intent,
    ServerEditValues reviewed,
    void Function() requireOwner,
  ) async {
    final current = await readServer(intent);
    requireOwner();
    if (!current.sameValues(reviewed)) {
      throw StateError('Server values changed');
    }
    retried.add(intent.id);
    _apply(intent);
  }

  void _apply(EditIntent intent) {
    if (intent.deletesDocument) {
      rows.remove(intent.path);
    } else {
      rows[intent.path] = {...?rows[intent.path], ...intent.fields};
    }
  }
}

class _FailingStore extends HiveSavedEditStore {
  @override
  Future<void> put(SavedEdit edit) async =>
      throw StateError('Disk unavailable');
}

class _DelayedStore extends HiveSavedEditStore {
  final started = Completer<void>();
  final continueWrite = Completer<void>();

  @override
  Future<void> put(SavedEdit edit) async {
    if (!started.isCompleted) started.complete();
    await continueWrite.future;
    await super.put(edit);
  }
}

class _TimedOutStore extends HiveSavedEditStore {
  final release = Completer<void>();
  late Future<void> firstWrite;
  int puts = 0;

  @override
  Future<void> put(SavedEdit edit) {
    puts++;
    if (puts == 1) return firstWrite = release.future;
    return super.put(edit);
  }
}
