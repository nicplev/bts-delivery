import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/delivery_visit.dart';
import '../providers/delivery_visit_provider.dart';
import '../providers/auth_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'delivery_day_list.dart';

class DeliveryVisitGate extends ConsumerWidget {
  const DeliveryVisitGate(
      {super.key, required this.visit, required this.child});

  final DeliveryVisit visit;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = deliveryVisitReadinessProvider(visit);
    final state = ref.watch(provider);
    final online = ref.watch(isOnlineProvider);
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final staff = ref.watch(currentStaffProvider);
    final member = staff.valueOrNull;
    final access = state.valueOrNull;
    if (access != null &&
        access.uid == uid &&
        access.status.canOpen(online: online) &&
        member != null &&
        member.uid == uid &&
        !staff.hasError &&
        !state.hasError &&
        (member.hasManagerAccess ||
            member.assignedSchoolIds.contains(visit.schoolId))) {
      return child;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('School visit'),
        leading: BackButton(onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }),
      ),
      body: Center(
        child: state.when(
          skipLoadingOnRefresh: false,
          loading: () => DeliveryMessage(
            icon: online ? Icons.downloading : Icons.cloud_off_outlined,
            title: online
                ? 'Preparing the school visit'
                : 'Checking saved visit records',
            description: online
                ? 'Saving classroom information for offline access.'
                : null,
          ),
          error: (_, __) => DeliveryMessage(
            icon: Icons.error_outline,
            title: 'Couldn’t prepare this school visit',
            description: 'Check your connection and try again.',
            action: TextButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('Retry')),
          ),
          data: (_) => DeliveryMessage(
            icon: Icons.cloud_off_outlined,
            title: 'This visit isn’t available offline yet',
            description:
                'Connect and open the visit to save the classroom records on this device.',
            action: TextButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('Retry')),
          ),
        ),
      ),
    );
  }
}
