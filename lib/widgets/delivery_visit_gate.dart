import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/delivery_visit.dart';
import '../providers/delivery_visit_provider.dart';
import '../providers/auth_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'delivery_day_list.dart';
import 'design/design.dart';

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
      // Imperative pushes can skip a nested GoRouter shell builder. Bind the
      // repository here so each visit page gets the same scope and access check.
      return ProviderScope(
        key: ValueKey(visit),
        overrides: [activeDeliveryVisitProvider.overrideWithValue(visit)],
        child: child,
      );
    }
    final message = state.when(
      skipLoadingOnRefresh: false,
      loading: () => DeliveryMessage(
        icon: online ? AppIcons.download : AppIcons.offline,
        title: online
            ? 'Preparing the school visit'
            : 'Checking saved visit records',
        description:
            online ? 'Saving classroom information for offline access.' : null,
      ),
      error: (_, __) => DeliveryMessage(
        icon: AppIcons.error,
        title: 'Couldn’t prepare this school visit',
        description: 'Check your connection and try again.',
        action: AppSecondaryButton(
          label: 'Retry',
          icon: AppIcons.retry,
          expand: false,
          onPressed: () => ref.invalidate(provider),
        ),
      ),
      data: (_) => DeliveryMessage(
        icon: AppIcons.offline,
        title: 'This visit isn’t available offline yet',
        description:
            'Connect and open the visit to save the classroom records on this device.',
        action: AppSecondaryButton(
          label: 'Retry',
          icon: AppIcons.retry,
          expand: false,
          onPressed: () => ref.invalidate(provider),
        ),
      ),
    );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppNavBar(
        showBack: true,
        backLabel: 'Back to deliveries',
        onBack: () {
          final router = GoRouter.maybeOf(context);
          if (router == null) {
            Navigator.maybePop(context);
          } else if (router.canPop()) {
            router.pop();
          } else {
            router.go('/home');
          }
        },
      ),
      body: ListView(
        padding: AppInsets.scroll(context),
        children: [
          const AppLargeTitle(title: 'School visit'),
          const SizedBox(height: AppTokens.sectionGap - 8),
          message,
        ],
      ),
    );
  }
}
