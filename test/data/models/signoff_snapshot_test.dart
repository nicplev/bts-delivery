import 'package:bts_delivery_app/models/offline/evidence_upload.dart';
import 'package:bts_delivery_app/models/signoff_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final time = DateTime.utc(2026, 11, 16);
  final row = {
    'yearLevel': 'Year 1',
    'classroomName': 'Room A',
    'status': 'incomplete',
    'expectedPacks': 12,
    'actualPacksDelivered': null,
    'consumables': <String, dynamic>{},
  };

  EvidenceUpload queued(String id, String delivery, SignOffSnapshot snapshot) =>
      EvidenceUpload(
        id: id,
        kind: EvidenceKind.signature,
        ownerUid: 'uid-a',
        schoolId: 'school-a',
        deliveryId: delivery,
        localFileName: '$id.png',
        storagePath: 'schools/school-a/signoffs/$id.png',
        createdAt: time,
        payload: {'typedName': 'A. Signer', 'snapshot': snapshot.toJson()},
      );

  test('signed snapshot retains exact quantities after source changes', () {
    final data = SignOffSnapshot.incomplete('school-a').summary
      ..['totalPacks'] = 12
      ..['classroomDeliveryDetails'] = [Map<String, dynamic>.from(row)];
    final frozen = SignOffSnapshot(
      sourceReadAt: time,
      serverReviewed: true,
      summary: data,
    );
    final item = queued('signature-1', 'visit-a', frozen);
    data['totalPacks'] = 90;
    (data['classroomDeliveryDetails'] as List).clear();
    final signed = SignedEvidence.fromUpload(
      EvidenceUpload.fromRecord(item.toRecord()),
    );
    final summary = signed.snapshot.export(
      evidenceId: signed.id,
      schoolId: signed.schoolId,
      typedName: signed.typedName,
      capturedAt: signed.capturedAt,
    );
    expect(summary.totalPacks, 12);
    expect(summary.classroomDeliveryDetails.single.expectedPacks, 12);
    expect(
        summary.classroomDeliveryDetails.single.actualPacksDelivered, isNull);
    expect(signed.matches(SignedEvidence.fromDocument(signed.toDocument())),
        isTrue);
  });

  test('different visits and corrections have distinct immutable identities',
      () {
    final frozen = SignOffSnapshot.incomplete('school-a');
    final first =
        SignedEvidence.fromUpload(queued('signature-1', 'visit-a', frozen));
    final correction =
        SignedEvidence.fromUpload(queued('signature-2', 'visit-a', frozen));
    final later =
        SignedEvidence.fromUpload(queued('signature-3', 'visit-b', frozen));
    expect(
        {first.signaturePath, correction.signaturePath, later.signaturePath}
            .length,
        3);
    expect(SignedEvidence.scopeKey(first.deliveryId),
        SignedEvidence.scopeKey(correction.deliveryId));
    expect(SignedEvidence.scopeKey(first.deliveryId),
        isNot(SignedEvidence.scopeKey(later.deliveryId)));
    expect(first.matches(correction), isFalse);
    expect(first.matches(later), isFalse);
  });

  test('cached evidence persists for review and cannot be exported as complete',
      () {
    final cached = SignOffSnapshot.incomplete('school-a');
    final record =
        SignedEvidence.fromUpload(queued('signature-1', 'visit-a', cached));
    expect(record.toDocument()['reviewStatus'], 'cached');
    expect(
        () => record.snapshot.export(
              evidenceId: record.id,
              schoolId: record.schoolId,
              typedName: record.typedName,
              capturedAt: record.capturedAt,
            ),
        throwsStateError);
  });

  test('invalid snapshot cannot be accepted as signed evidence', () {
    final corrupt = SignOffSnapshot(
      sourceReadAt: time,
      serverReviewed: true,
      summary: {
        'schoolName': 'School',
        'classroomDeliveryDetails': [row]
      },
    );
    expect(
      () =>
          SignedEvidence.fromUpload(queued('signature-1', 'visit-a', corrupt)),
      throwsA(isA<TypeError>()),
    );
    final empty = SignOffSnapshot(
      sourceReadAt: time,
      serverReviewed: true,
      summary: SignOffSnapshot.incomplete('school-a').summary,
    );
    expect(
      () => SignedEvidence.fromUpload(queued('signature-2', 'visit-a', empty)),
      throwsFormatException,
    );
  });
}
