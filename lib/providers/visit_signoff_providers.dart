import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery_visit.dart';
import '../models/offline/evidence_upload.dart';
import '../models/signoff_snapshot.dart';
import 'auth_providers.dart';
import 'offline_delivery_providers.dart';
import 'repository_providers.dart';

/// The latest signed record of one delivery visit, read the same way as the
/// visit's Sign-off tab: a listener on the visit's sign-off pointer
/// (`schools/{schoolId}/signoffPointers/visit-{deliveryId}`) plus one read of
/// the record it names. Works from the Firestore cache offline.
///
/// Only watched for the visits on screen (today's, or the selected calendar
/// day's) and disposed with them. Visits outside the account's schools are
/// never read.
final visitSignedEvidenceProvider = StreamProvider.autoDispose
    .family<SignedEvidence?, DeliveryVisit>((ref, visit) {
  if (!ref.watch(isAdminProvider)) {
    final staff = ref.watch(currentStaffProvider);
    if (staff.isLoading && !staff.hasValue) return const Stream.empty();
    final member = staff.valueOrNull;
    if (staff.hasError ||
        member == null ||
        !(member.hasManagerAccess ||
            member.assignedSchoolIds.contains(visit.schoolId))) {
      return Stream.value(null);
    }
  }
  return ref
      .watch(baseSchoolsRepositoryProvider)
      .watchSignedEvidence(visit.schoolId, visit.deliveryId);
});

/// Whether a delivery visit has been signed off: it has a signed record, or
/// a signature for it is saved on this device and waiting to upload (the
/// receiver has signed).
///
/// While either source is loading or cannot be read the visit counts as not
/// signed off, so work is never hidden behind an unknown state.
final visitSignedOffProvider =
    Provider.autoDispose.family<bool, DeliveryVisit>((ref, visit) {
  final queued = ref.watch(evidenceUploadsProvider).valueOrNull?.items.any(
            (item) =>
                item.kind == EvidenceKind.signature &&
                item.schoolId == visit.schoolId &&
                item.deliveryId == visit.deliveryId,
          ) ??
      false;
  if (queued) return true;
  return ref.watch(visitSignedEvidenceProvider(visit)).valueOrNull != null;
});
