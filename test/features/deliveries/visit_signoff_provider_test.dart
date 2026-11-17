import 'dart:async';

import 'package:bts_delivery_app/models/delivery_visit.dart';
import 'package:bts_delivery_app/models/offline/evidence_upload.dart';
import 'package:bts_delivery_app/models/signoff_snapshot.dart';
import 'package:bts_delivery_app/models/staff.dart';
import 'package:bts_delivery_app/providers/auth_providers.dart';
import 'package:bts_delivery_app/providers/offline_delivery_providers.dart';
import 'package:bts_delivery_app/providers/repository_providers.dart';
import 'package:bts_delivery_app/providers/visit_signoff_providers.dart';
import 'package:bts_delivery_app/repositories/schools_repository.dart';
import 'package:bts_delivery_app/services/offline/evidence_upload_worker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assigned = DeliveryVisit(deliveryId: 'd1', schoolId: 'one');
  const unassigned = DeliveryVisit(deliveryId: 'd2', schoolId: 'other');

  ProviderContainer container(
    _Schools schools, {
    String role = 'staff',
    List<EvidenceUpload> queued = const [],
    Stream<EvidenceUploadStatus>? uploads,
  }) {
    final result = ProviderContainer(overrides: [
      baseSchoolsRepositoryProvider.overrideWithValue(schools),
      isAdminProvider.overrideWithValue(role == 'admin'),
      currentStaffProvider.overrideWith((_) => Stream.value(Staff(
            id: 'staff',
            name: 'Driver',
            role: role,
            assignedSchoolIds: const ['one'],
            createdAt: DateTime(2025),
          ))),
      evidenceUploadsProvider.overrideWith((_) =>
          uploads ??
          Stream.value(EvidenceUploadStatus(
            items: queued,
            activeId: null,
            legacyReviewCount: 0,
            localError: false,
          ))),
    ]);
    addTearDown(result.dispose);
    return result;
  }

  test('reads the visit sign-off pointer only for schools the staff can open',
      () async {
    final schools = _Schools();
    final c = container(schools);
    c.listen(visitSignedOffProvider(assigned), (_, __) {});
    c.listen(visitSignedOffProvider(unassigned), (_, __) {});
    await c.read(visitSignedEvidenceProvider(assigned).future);
    await c.read(visitSignedEvidenceProvider(unassigned).future);

    expect(schools.reads, [('one', 'd1')]);
    expect(c.read(visitSignedOffProvider(assigned)), isFalse);
    expect(c.read(visitSignedOffProvider(unassigned)), isFalse);

    schools.records['one/d1']!.add(_evidence());
    await c.pump();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(visitSignedOffProvider(assigned)), isTrue);
  });

  test('managers read any visit and stop listening when the row goes away',
      () async {
    final schools = _Schools();
    final c = container(schools, role: 'manager');
    final sub = c.listen(visitSignedOffProvider(unassigned), (_, __) {});
    await c.read(visitSignedEvidenceProvider(unassigned).future);
    expect(schools.reads, [('other', 'd2')]);

    sub.close();
    await c.pump();
    expect(c.exists(visitSignedEvidenceProvider(unassigned)), isFalse);
    expect(schools.records['other/d2']!.hasListener, isFalse);
  });

  test('an unreadable record or upload queue is treated as not signed off',
      () async {
    final schools = _Schools();
    final c = container(schools,
        uploads: Stream.error(StateError('Upload queue unavailable')));
    c.listen(visitSignedOffProvider(assigned), (_, __) {});
    await c.read(visitSignedEvidenceProvider(assigned).future);
    schools.records['one/d1']!.addError(StateError('Signed evidence missing'));
    await Future<void>.delayed(Duration.zero);
    await c.pump();
    expect(c.read(visitSignedEvidenceProvider(assigned)).hasError, isTrue);
    expect(c.read(visitSignedOffProvider(assigned)), isFalse);
  });

  test('a signature waiting to upload for the visit counts as signed off',
      () async {
    final schools = _Schools();
    final c = container(schools, queued: [
      EvidenceUpload(
        id: 'sig',
        kind: EvidenceKind.signature,
        ownerUid: 'driver',
        schoolId: 'one',
        deliveryId: 'd1',
        localFileName: 'sig.png',
        storagePath: 'schools/one/signoffs/sig.png',
        createdAt: DateTime(2025),
      ),
    ]);
    c.listen(visitSignedOffProvider(assigned), (_, __) {});
    await c.read(evidenceUploadsProvider.future);
    await c.pump();
    expect(c.read(visitSignedOffProvider(assigned)), isTrue);
  });
}

SignedEvidence _evidence() => SignedEvidence(
      id: 'e1',
      schoolId: 'one',
      deliveryId: 'd1',
      ownerUid: 'driver',
      signaturePath: 'schools/one/signoffs/e1.png',
      typedName: 'Receiver',
      capturedAt: DateTime(2025),
      snapshot: SignOffSnapshot(
        sourceReadAt: DateTime(2025),
        serverReviewed: false,
        summary: const {},
      ),
    );

class _Schools implements SchoolsRepository {
  final reads = <(String, String?)>[];
  final records = <String, StreamController<SignedEvidence?>>{};

  @override
  Stream<SignedEvidence?> watchSignedEvidence(
      String schoolId, String? deliveryId) {
    reads.add((schoolId, deliveryId));
    final controller = records['$schoolId/$deliveryId'] =
        StreamController<SignedEvidence?>.broadcast();
    scheduleMicrotask(() => controller.add(null));
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
