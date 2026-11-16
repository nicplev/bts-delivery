import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../../models/delivery_visit.dart';

class FieldDraftTarget {
  const FieldDraftTarget({
    required this.schoolId,
    required this.form,
    this.deliveryId,
    this.yearLevelId,
    this.classroomId,
    this.entityId,
  });

  final String schoolId;
  final String form;
  final String? deliveryId;
  final String? yearLevelId;
  final String? classroomId;
  final String? entityId;

  String keyFor(String uid) {
    final visit = deliveryId;
    final root = visit == null
        ? 'schools/$schoolId'
        : DeliveryVisit(deliveryId: visit, schoolId: schoolId).workspacePath;
    final parts = [uid, root, yearLevelId, classroomId, form, entityId];
    return sha256.convert(utf8.encode(jsonEncode(parts))).toString();
  }
}

class FieldDraft {
  FieldDraft({required this.revision, required Map<String, String> values})
      : values = Map.unmodifiable(values);

  /// Also used as the edit ID for an unchanged save retried after restart.
  final String revision;
  final Map<String, String> values;
}

abstract interface class FieldDraftStore {
  Future<FieldDraft?> read(String key);
  Future<void> write(String key, FieldDraft draft);

  /// Remove only the submitted revision, leaving any subsequent draft intact.
  Future<void> remove(String key, {required String revision});
}

class HiveFieldDraftStore implements FieldDraftStore {
  HiveFieldDraftStore(this._box);

  final Box<Map> _box;

  static Future<HiveFieldDraftStore> open() async =>
      HiveFieldDraftStore(await Hive.openBox<Map>('field_form_drafts'));

  @override
  Future<FieldDraft?> read(String key) async {
    final data = _box.get(key);
    if (data == null) return null;
    return FieldDraft(
      revision: data['revision'] as String,
      values: Map<String, String>.from(data['values'] as Map),
    );
  }

  @override
  Future<void> write(String key, FieldDraft draft) => _box.put(key, {
        'revision': draft.revision,
        'values': draft.values,
      });

  @override
  Future<void> remove(String key, {required String revision}) async {
    if (_box.get(key)?['revision'] == revision) await _box.delete(key);
  }
}
