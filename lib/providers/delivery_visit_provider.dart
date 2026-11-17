import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery_visit.dart';
import '../services/delivery_visit_access.dart';
import '../services/offline/connectivity_service.dart';
import 'auth_providers.dart';

/// Overridden only by the visit route's ProviderScope.
final activeDeliveryVisitProvider = Provider<DeliveryVisit?>(
  (_) => null,
  dependencies: const [],
);

typedef VisitReadiness = ({String uid, DeliveryVisitReadiness status});

final deliveryVisitReadinessProvider = FutureProvider.autoDispose
    .family<VisitReadiness, DeliveryVisit>((ref, visit) async {
  final uid =
      ref.watch(authStateProvider.select((value) => value.valueOrNull?.uid));
  final staff = ref.watch(currentStaffProvider);
  final online = ref.watch(isOnlineProvider);
  final openVisit = ref.watch(deliveryVisitAccessProvider);
  final member = await ref.watch(currentStaffProvider.future);
  if (uid == null ||
      staff.hasError ||
      member == null ||
      member.uid != uid ||
      !(member.hasManagerAccess ||
          member.assignedSchoolIds.contains(visit.schoolId))) {
    throw StateError('This delivery is unavailable to this account.');
  }
  final status = await openVisit.open(visit, uid: uid, online: online);
  return (uid: uid, status: status);
});

final deliveryVisitAccessProvider = Provider<DeliveryVisitAccess>((_) {
  return DeliveryVisitAccess(FirebaseFirestore.instance, FirebaseAuth.instance);
});
