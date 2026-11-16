import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../delivery_visit.dart';

enum SavedEditKind {
  classroomName,
  classroomStatus,
  noteCreate,
  noteContent,
  noteDelete,
  packTotal,
  consumableCount,
  checklist,
}

enum SavedEditState {
  waiting,
  queued,
  review,
  rejected,
  matched,
  acknowledged,
  dismissed
}

/// Canonical visit-relative target and the values the user chose to save.
/// Timestamp fields in [fields] are encoded as UTC microseconds.
class EditIntent {
  EditIntent({
    required this.id,
    required this.ownerUid,
    required this.schoolId,
    required this.kind,
    required this.capturedAt,
    required Map<String, Object?> values,
    required this.updatedBy,
    this.deliveryId,
    this.yearLevelId,
    this.classroomId,
    this.itemId,
    this.itemLabel,
    this.rememberId = false,
  }) : values = Map.unmodifiable(values) {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw const FormatException('Invalid saved edit identifier');
    }
    _segment(ownerUid);
    _segment(schoolId);
    if (deliveryId != null) _segment(deliveryId);
    if (kind == SavedEditKind.checklist) {
      _segment(deliveryId);
      _segment(itemId);
    } else {
      _segment(yearLevelId);
      _segment(classroomId);
      if (kind == SavedEditKind.consumableCount ||
          kind == SavedEditKind.noteContent ||
          kind == SavedEditKind.noteDelete) {
        _segment(itemId);
      }
    }
    final expectedKeys = switch (kind) {
      SavedEditKind.classroomName => {'name'},
      SavedEditKind.classroomStatus => {
          'completionStatus',
          'actualPacksDelivered',
        },
      SavedEditKind.noteCreate => {'content', 'author'},
      SavedEditKind.noteContent => {'content'},
      SavedEditKind.noteDelete => {'content', 'author', 'createdAt'},
      SavedEditKind.packTotal => {'total'},
      SavedEditKind.consumableCount => {'actualQuantityDelivered'},
      SavedEditKind.checklist => {'isCompleted', 'completedBy'},
    };
    if (values.keys.toSet().difference(expectedKeys).isNotEmpty ||
        values.length != expectedKeys.length ||
        values.values.any((value) =>
            value != null &&
            value is! String &&
            value is! bool &&
            value is! int)) {
      throw const FormatException('Invalid saved edit fields');
    }
  }

  final String id;
  final String ownerUid;
  final String schoolId;
  final String? deliveryId;
  final String? yearLevelId;
  final String? classroomId;
  final String? itemId;
  final String? itemLabel;
  final String updatedBy;
  final DateTime capturedAt;
  final SavedEditKind kind;
  final Map<String, Object?> values;
  final bool rememberId;

  DeliveryVisit? get visit => deliveryId == null
      ? null
      : DeliveryVisit(deliveryId: deliveryId!, schoolId: schoolId);

  String get classroomPath =>
      '${visit?.workspacePath ?? 'schools/$schoolId'}/yearLevels/$yearLevelId/classrooms/$classroomId';

  String get path => switch (kind) {
        SavedEditKind.classroomName ||
        SavedEditKind.classroomStatus =>
          classroomPath,
        SavedEditKind.noteCreate => '$classroomPath/notes/$id',
        SavedEditKind.noteContent ||
        SavedEditKind.noteDelete =>
          '$classroomPath/notes/$itemId',
        SavedEditKind.packTotal => '$classroomPath/packTotals/$id',
        SavedEditKind.consumableCount => '$classroomPath/consumables/$itemId',
        SavedEditKind.checklist =>
          'deliveries/$deliveryId/preDeliveryChecklist/$itemId',
      };

  bool get createsDocument =>
      kind == SavedEditKind.noteCreate || kind == SavedEditKind.packTotal;
  bool get deletesDocument => kind == SavedEditKind.noteDelete;
  bool get isClassroom =>
      kind == SavedEditKind.classroomName ||
      kind == SavedEditKind.classroomStatus;

  String get title => switch (kind) {
        SavedEditKind.classroomName => 'Classroom name',
        SavedEditKind.classroomStatus => 'Classroom delivery status',
        SavedEditKind.noteCreate => 'New classroom note',
        SavedEditKind.noteContent => 'Classroom note',
        SavedEditKind.noteDelete => 'Delete classroom note',
        SavedEditKind.packTotal => 'Pack count',
        SavedEditKind.consumableCount => 'Delivered quantity',
        SavedEditKind.checklist => 'Loading checklist',
      };

  Map<String, Object?> get fields => {
        ...values,
        if (createsDocument) 'createdAt': capturedAt.microsecondsSinceEpoch,
        if (kind == SavedEditKind.checklist)
          'completedAt': values['isCompleted'] == true
              ? capturedAt.microsecondsSinceEpoch
              : null,
      };

  String get key => '$ownerUid:$id';
  String get fingerprint {
    final keys = values.keys.toList()..sort();
    return sha256
        .convert(utf8.encode(jsonEncode([
          kind.name,
          path,
          {for (final key in keys) key: values[key]},
        ])))
        .toString();
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'ownerUid': ownerUid,
        'schoolId': schoolId,
        'deliveryId': deliveryId,
        'yearLevelId': yearLevelId,
        'classroomId': classroomId,
        'itemId': itemId,
        'itemLabel': itemLabel,
        'updatedBy': updatedBy,
        'kind': kind.name,
        'capturedAt': capturedAt.microsecondsSinceEpoch,
        'values': values,
        'rememberId': rememberId,
      };

  factory EditIntent.fromJson(Map<String, Object?> json) => EditIntent(
        id: json['id'] as String,
        ownerUid: json['ownerUid'] as String,
        schoolId: json['schoolId'] as String,
        deliveryId: json['deliveryId'] as String?,
        yearLevelId: json['yearLevelId'] as String?,
        classroomId: json['classroomId'] as String?,
        itemId: json['itemId'] as String?,
        itemLabel: json['itemLabel'] as String?,
        updatedBy: json['updatedBy'] as String,
        kind: SavedEditKind.values.byName(json['kind'] as String),
        capturedAt: DateTime.fromMicrosecondsSinceEpoch(
            json['capturedAt'] as int,
            isUtc: true),
        values: Map<String, Object?>.from(json['values'] as Map),
        rememberId: json['rememberId'] == true,
      );

  static void _segment(String? value) {
    if (value == null ||
        value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.length > 128) {
      throw const FormatException('Invalid saved edit location');
    }
  }
}

class SavedEdit {
  const SavedEdit(this.intent, this.state);

  final EditIntent intent;
  final SavedEditState state;
}

class ServerEditValues {
  ServerEditValues({
    required this.exists,
    required this.hasPendingWrites,
    required Map<String, Object?> fields,
  }) : fields = Map.unmodifiable(fields);

  final bool exists;
  final bool hasPendingWrites;
  final Map<String, Object?> fields;

  bool matches(EditIntent intent) => intent.deletesDocument
      ? !exists
      : exists && _fieldsMatch(fields, intent.fields);

  bool sameValues(ServerEditValues other) =>
      exists == other.exists && _fieldsMatch(fields, other.fields);

  bool _fieldsMatch(Map<String, Object?> left, Map<String, Object?> right) =>
      left.length == right.length &&
      right.entries.every((entry) =>
          left.containsKey(entry.key) && left[entry.key] == entry.value);
}
