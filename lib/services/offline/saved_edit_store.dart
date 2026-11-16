import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import '../../models/offline/saved_edit.dart';

typedef EditReceiptRecord = ({
  String fingerprint,
  SavedEditState state,
  SavedEdit? edit
});

abstract interface class SavedEditStore {
  Future<EditReceiptRecord?> read(String ownerUid, String id);
  Future<List<SavedEdit>> pending(String ownerUid);
  Stream<List<SavedEdit>> watch(String ownerUid);
  Future<void> put(SavedEdit edit);
  Future<void> finish(EditIntent intent, {bool dismissed = false});
}

class HiveSavedEditStore implements SavedEditStore {
  Future<LazyBox<Map>>? _opening;

  Future<LazyBox<Map>> _box() async {
    try {
      return await (_opening ??=
          Hive.openLazyBox<Map>('ordinary_saved_edits_v1'));
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<EditReceiptRecord?> read(String ownerUid, String id) async {
    final value = await (await _box()).get('$ownerUid:$id');
    if (value == null) return null;
    return _decode(value, ownerUid);
  }

  EditReceiptRecord _decode(Map value, String ownerUid) {
    if (value['ownerUid'] != ownerUid) {
      throw const FormatException('Saved edit belongs to another account');
    }
    final state = SavedEditState.values.byName(value['state'] as String);
    final edit = state == SavedEditState.acknowledged ||
            state == SavedEditState.dismissed
        ? null
        : SavedEdit(
            EditIntent.fromJson(Map<String, Object?>.from(value)),
            state,
          );
    return (
      fingerprint: value['fingerprint'] as String,
      state: state,
      edit: edit
    );
  }

  Future<List<SavedEdit>> _pending(LazyBox<Map> box, String ownerUid) async {
    final prefix = '$ownerUid:';
    final keys = box.keys
        .whereType<String>()
        .where(
            (key) => key.startsWith(prefix) && key.length == prefix.length + 36)
        .toList();
    final edits = <SavedEdit>[];
    for (final key in keys) {
      final value = await box.get(key);
      if (value == null) continue;
      final edit = _decode(value, ownerUid).edit;
      if (edit != null) edits.add(edit);
    }
    edits.sort((a, b) => a.intent.capturedAt.compareTo(b.intent.capturedAt));
    return edits;
  }

  @override
  Future<List<SavedEdit>> pending(String ownerUid) async =>
      _pending(await _box(), ownerUid);

  @override
  Stream<List<SavedEdit>> watch(String ownerUid) async* {
    final box = await _box();
    yield* Stream.multi((stream) {
      var generation = 0;
      Future<void> emit() async {
        final requested = ++generation;
        try {
          final edits = await _pending(box, ownerUid);
          if (requested == generation) stream.add(edits);
        } catch (error, stack) {
          if (requested == generation) stream.addError(error, stack);
        }
      }

      final subscription = box
          .watch()
          .listen((_) => unawaited(emit()), onError: stream.addError);
      stream.onCancel = () {
        generation++;
        return subscription.cancel();
      };
      unawaited(emit());
    });
  }

  @override
  Future<void> put(SavedEdit edit) async {
    final intent = edit.intent;
    await (await _box()).put(intent.key, {
      ...intent.toJson(),
      'state': edit.state.name,
      'fingerprint': intent.fingerprint,
    });
  }

  @override
  Future<void> finish(EditIntent intent, {bool dismissed = false}) async {
    final box = await _box();
    if (intent.rememberId) {
      await box.put(intent.key, {
        'ownerUid': intent.ownerUid,
        'fingerprint': intent.fingerprint,
        'state':
            (dismissed ? SavedEditState.dismissed : SavedEditState.acknowledged)
                .name,
      });
    } else {
      await box.delete(intent.key);
    }
  }
}
