import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'offline/evidence_upload.dart';
import 'school.dart';

/// The export data reviewed by the signer, encoded using JSON primitives for
/// persistence on this device. A cached capture always requires review.
class SignOffSnapshot {
  SignOffSnapshot({
    required this.sourceReadAt,
    required this.serverReviewed,
    required Map<String, dynamic> summary,
  }) : _summaryJson = jsonEncode(summary) {
    if (utf8.encode(_summaryJson).length > 750 * 1024) {
      throw const FormatException('The snapshot is too large to save');
    }
  }

  final DateTime sourceReadAt;
  final bool serverReviewed;
  final String _summaryJson;

  Map<String, dynamic> get summary =>
      jsonDecode(_summaryJson) as Map<String, dynamic>;

  int get totalPacks => summary['totalPacks'] as int;

  List<dynamic> get classrooms => summary['classroomDeliveryDetails'] as List;

  /// Compares what the signer reviewed, excluding the time of the read.
  bool hasSameReviewContent(SignOffSnapshot other) =>
      serverReviewed == other.serverReviewed &&
      jsonEncode(_sorted(summary)) == jsonEncode(_sorted(other.summary));

  Map<String, dynamic> toJson() => {
        'sourceReadAt': sourceReadAt.toUtc().toIso8601String(),
        'serverReviewed': serverReviewed,
        'summary': summary,
      };

  factory SignOffSnapshot.fromJson(Map<String, dynamic> data) =>
      SignOffSnapshot(
        sourceReadAt: DateTime.parse(data['sourceReadAt'] as String),
        serverReviewed: data['serverReviewed'] as bool,
        summary: Map<String, dynamic>.from(data['summary'] as Map),
      );

  factory SignOffSnapshot.incomplete(String schoolId) => SignOffSnapshot(
        sourceReadAt: DateTime.now().toUtc(),
        serverReviewed: false,
        summary: {
          'schoolName': schoolId,
          'totalPacks': 0,
          'packTotalsByYearLevel': <String, int>{},
          'packTotalsByClassroom': <String, dynamic>{},
          'consumablesTotals': <String, dynamic>{},
          'consumablesByYearLevel': <String, dynamic>{},
          'consumablesByClassroom': <String, dynamic>{},
          'classroomDeliveryDetails': <dynamic>[],
          'photoUrls': <String>[],
          'notesByClassroom': <String, dynamic>{},
        },
      );

  SignedSchoolSummary export({
    required String evidenceId,
    required String schoolId,
    required String typedName,
    required DateTime capturedAt,
    String? signatureUrl,
  }) {
    if (!serverReviewed) {
      throw StateError('Cached evidence must be reviewed before export');
    }
    return _asSummary(
      evidenceId: evidenceId,
      schoolId: schoolId,
      typedName: typedName,
      capturedAt: capturedAt,
      signatureUrl: signatureUrl,
    );
  }

  SignedSchoolSummary _asSummary({
    required String evidenceId,
    required String schoolId,
    required String typedName,
    required DateTime capturedAt,
    String? signatureUrl,
  }) {
    return SignedSchoolSummary.fromJson({
      ...summary,
      'id': evidenceId,
      'schoolId': schoolId,
      'signedBy': typedName,
      'signedDate': Timestamp.fromDate(capturedAt),
      'createdAt': Timestamp.fromDate(capturedAt),
      'signatureUrl': signatureUrl,
    });
  }
}

class SignedEvidence {
  const SignedEvidence({
    required this.id,
    required this.schoolId,
    required this.ownerUid,
    required this.signaturePath,
    required this.typedName,
    required this.capturedAt,
    required this.snapshot,
    this.deliveryId,
  });

  final String id;
  final String schoolId;
  final String? deliveryId;
  final String ownerUid;
  final String signaturePath;
  final String typedName;
  final DateTime capturedAt;
  final SignOffSnapshot snapshot;

  static String scopeKey(String? deliveryId) =>
      deliveryId == null ? 'school-only' : 'visit-$deliveryId';

  factory SignedEvidence.fromUpload(EvidenceUpload item) {
    final name = (item.payload['typedName'] as String).trim();
    final snapshot = SignOffSnapshot.fromJson(
      item.payload['snapshot'] as Map<String, dynamic>,
    );
    if (item.kind != EvidenceKind.signature ||
        name.isEmpty ||
        name.length > 200 ||
        item.ownerUid.isEmpty ||
        (item.deliveryId?.isEmpty ?? false) ||
        (item.deliveryId?.contains('/') ?? false) ||
        (snapshot.serverReviewed && snapshot.classrooms.isEmpty) ||
        item.storagePath !=
            'schools/${item.schoolId}/signoffs/${item.id}.png') {
      throw const FormatException('Invalid signed evidence');
    }

    // Validate the frozen inputs before making an immutable record.
    snapshot._asSummary(
      evidenceId: item.id,
      schoolId: item.schoolId,
      typedName: name,
      capturedAt: item.createdAt,
    );
    return SignedEvidence(
      id: item.id,
      schoolId: item.schoolId,
      deliveryId: item.deliveryId,
      ownerUid: item.ownerUid,
      signaturePath: item.storagePath,
      typedName: name,
      capturedAt: item.createdAt,
      snapshot: snapshot,
    );
  }

  factory SignedEvidence.fromDocument(Map<String, dynamic> data) {
    final snapshot = SignOffSnapshot.fromJson(
      Map<String, dynamic>.from(data['snapshot'] as Map),
    );
    if (data['reviewStatus'] !=
        (snapshot.serverReviewed ? 'serverReviewed' : 'cached')) {
      throw const FormatException('Invalid evidence review state');
    }
    return SignedEvidence(
      id: data['id'] as String,
      schoolId: data['schoolId'] as String,
      deliveryId: data['deliveryId'] as String?,
      ownerUid: data['ownerUid'] as String,
      signaturePath: data['signaturePath'] as String,
      typedName: data['typedName'] as String,
      capturedAt: (data['capturedAt'] as Timestamp).toDate(),
      snapshot: snapshot,
    );
  }

  bool matches(SignedEvidence other) =>
      id == other.id &&
      schoolId == other.schoolId &&
      deliveryId == other.deliveryId &&
      ownerUid == other.ownerUid &&
      signaturePath == other.signaturePath &&
      typedName == other.typedName &&
      capturedAt.isAtSameMomentAs(other.capturedAt) &&
      jsonEncode(_sorted(snapshot.toJson())) ==
          jsonEncode(_sorted(other.snapshot.toJson()));

  Map<String, dynamic> toDocument() => {
        'id': id,
        'schoolId': schoolId,
        'deliveryId': deliveryId,
        'ownerUid': ownerUid,
        'signaturePath': signaturePath,
        'typedName': typedName,
        'capturedAt': Timestamp.fromDate(capturedAt),
        'reviewStatus': snapshot.serverReviewed ? 'serverReviewed' : 'cached',
        'snapshot': snapshot.toJson(),
      };
}

Object? _sorted(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}
