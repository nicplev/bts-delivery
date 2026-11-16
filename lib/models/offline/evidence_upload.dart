import 'dart:convert';

import '../delivery_visit.dart';

enum EvidenceKind { photo, signature }

enum EvidenceUploadError { missingFile, accessDenied, uploadFailed, saveFailed }

class EvidenceUpload {
  const EvidenceUpload({
    required this.id,
    required this.kind,
    required this.ownerUid,
    required this.schoolId,
    required this.localFileName,
    required this.storagePath,
    required this.createdAt,
    this.deliveryId,
    this.yearLevelId,
    this.classroomId,
    this.payload = const {},
    this.attempts = 0,
    this.retryAt,
    this.error,
    this.paused = false,
    this.uploaded = false,
    this.acknowledged = false,
  });

  final String id;
  final EvidenceKind kind;
  final String ownerUid;
  final String schoolId;
  final String localFileName;
  final String storagePath;
  final DateTime createdAt;
  final String? deliveryId;
  final String? yearLevelId;
  final String? classroomId;
  final Map<String, dynamic> payload;
  final int attempts;
  final DateTime? retryAt;
  final EvidenceUploadError? error;
  final bool paused;
  final bool uploaded;
  final bool acknowledged;

  bool get needsAttention => paused || (error != null && retryAt == null);

  String get statusText {
    if (paused) return 'Paused on this device';
    return switch (error) {
      EvidenceUploadError.missingFile => 'Local file missing',
      EvidenceUploadError.accessDenied => 'Access denied',
      EvidenceUploadError.uploadFailed ||
      EvidenceUploadError.saveFailed =>
        retryAt == null ? 'Action required' : 'Waiting to retry',
      null => 'Saved on this device',
    };
  }

  factory EvidenceUpload.fromRecord(Map<dynamic, dynamic> json) =>
      EvidenceUpload(
        id: json['id'] as String,
        kind: EvidenceKind.values.byName(json['kind'] as String),
        ownerUid: json['ownerUid'] as String,
        schoolId: json['schoolId'] as String,
        localFileName: json['localFileName'] as String,
        storagePath: json['storagePath'] as String,
        createdAt: json['createdAt'] as DateTime,
        deliveryId: json['deliveryId'] as String?,
        yearLevelId: json['yearLevelId'] as String?,
        classroomId: json['classroomId'] as String?,
        payload: jsonDecode(json['payload'] as String) as Map<String, dynamic>,
        attempts: json['attempts'] as int,
        retryAt: json['retryAt'] as DateTime?,
        error: json['error'] == null
            ? null
            : EvidenceUploadError.values.byName(json['error'] as String),
        paused: json['paused'] as bool,
        uploaded: json['uploaded'] as bool,
        acknowledged: json['acknowledged'] as bool,
      );

  Map<String, dynamic> toRecord() => {
        'id': id,
        'kind': kind.name,
        'ownerUid': ownerUid,
        'schoolId': schoolId,
        'localFileName': localFileName,
        'storagePath': storagePath,
        'createdAt': createdAt,
        'deliveryId': deliveryId,
        'yearLevelId': yearLevelId,
        'classroomId': classroomId,
        'payload': jsonEncode(payload),
        'attempts': attempts,
        'retryAt': retryAt,
        'error': error?.name,
        'paused': paused,
        'uploaded': uploaded,
        'acknowledged': acknowledged,
      };

  EvidenceUpload updateProgress({
    int? attempts,
    DateTime? retryAt,
    EvidenceUploadError? error,
    bool? paused,
    bool? uploaded,
    bool? acknowledged,
  }) =>
      EvidenceUpload(
        id: id,
        kind: kind,
        ownerUid: ownerUid,
        schoolId: schoolId,
        localFileName: localFileName,
        storagePath: storagePath,
        createdAt: createdAt,
        deliveryId: deliveryId,
        yearLevelId: yearLevelId,
        classroomId: classroomId,
        payload: payload,
        attempts: attempts ?? this.attempts,
        retryAt: retryAt,
        error: error,
        paused: paused ?? this.paused,
        uploaded: uploaded ?? this.uploaded,
        acknowledged: acknowledged ?? this.acknowledged,
      );
}

String photoStoragePath(
  String schoolId,
  String yearLevelId,
  String classroomId,
  String id, {
  String? deliveryId,
}) {
  final root = deliveryId == null
      ? 'schools/$schoolId'
      : DeliveryVisit(deliveryId: deliveryId, schoolId: schoolId).workspacePath;
  return '$root/yearLevels/$yearLevelId/classrooms/$classroomId/photos/$id.jpg';
}
