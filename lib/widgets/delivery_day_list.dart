import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/delivery.dart';
import '../models/delivery_visit.dart';
import '../providers/auth_providers.dart';
import '../providers/deliveries_providers.dart';
import '../providers/pre_delivery_checklist_providers.dart';
import '../providers/repository_providers.dart';
import '../services/date_utils.dart';
import '../services/offline/connectivity_service.dart';
import 'pre_delivery_checklist_dialog.dart';

class DeliveryDayList extends ConsumerWidget {
  const DeliveryDayList({
    super.key,
    required this.date,
    required this.deliveries,
    required this.onRetry,
    this.calendar,
  });

  final DateTime date;
  final AsyncValue<List<Delivery>> deliveries;
  final VoidCallback onRetry;
  final Widget? calendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(connectivityStatusProvider).valueOrNull ==
        ConnectivityStatus.offline;

    return CustomScrollView(
      slivers: [
        if (calendar != null) SliverToBoxAdapter(child: calendar),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              MaterialLocalizations.of(context).formatFullDate(date),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        deliveries.when(
          skipLoadingOnRefresh: false,
          loading: () => SliverToBoxAdapter(
            child: offline
                ? const DeliveryMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Checking saved deliveries',
                    description:
                        'A connection may be needed to load this date.',
                  )
                : const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
          ),
          error: (_, __) => SliverToBoxAdapter(
            child: DeliveryMessage(
              icon: Icons.error_outline,
              title: 'Couldn’t load deliveries',
              description: offline ? 'Reconnect, then try again.' : null,
              action:
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return SliverToBoxAdapter(
                child: DeliveryMessage(
                  icon: Icons.local_shipping_outlined,
                  title: offline
                      ? 'No saved deliveries for this date'
                      : 'No deliveries scheduled',
                ),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final delivery = items[index];
                    return Padding(
                      key: ValueKey(delivery.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DeliveryCard(delivery: delivery),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class DeliveryMessage extends StatelessWidget {
  const DeliveryMessage({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(description!, textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: 8),
            action!,
          ],
        ],
      ),
    );
  }
}

class _DeliveryCard extends ConsumerWidget {
  const _DeliveryCard({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final canEdit = ref.watch(canAssignDeliveriesProvider);
    final team = canEdit
        ? ref.watch(schoolStaffProvider(delivery.schoolId)).valueOrNull
        : null;
    final staffNames =
        team?.map((staff) => staff.name).toList() ?? delivery.staffNames;
    final checklist = ref.watch(deliveryChecklistStatusProvider(delivery.id));
    final checklistIcon = checklist.when(
      data: (complete) => complete ? Icons.task_alt : Icons.checklist,
      error: (_, __) => Icons.error_outline,
      loading: () => Icons.checklist,
    );
    final checklistLabel = checklist.when(
      data: (complete) => complete ? 'Checklist complete' : 'Checklist',
      error: (_, __) => 'Checklist status unavailable',
      loading: () => 'Checklist',
    );
    final time = delivery.time;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    delivery.schoolName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (canEdit)
                  PopupMenuButton<String>(
                    tooltip: 'Manage delivery',
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (isAdmin)
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      if (isAdmin)
                        const PopupMenuItem(
                          value: 'staff',
                          child: Text('Manage staff'),
                        ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          context.go('/deliveries/${delivery.id}/edit');
                        case 'delete':
                          _deleteDelivery(context, ref);
                        case 'staff':
                          _openStaffAllocation(context, ref);
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Open school'),
                  onPressed: () => context.push(schoolWorkPath(
                    delivery.schoolId,
                    visit: DeliveryVisit(
                        deliveryId: delivery.id, schoolId: delivery.schoolId),
                  )),
                ),
                TextButton.icon(
                  icon: Icon(checklistIcon),
                  label: Text(checklistLabel),
                  onPressed: () async {
                    await showPreDeliveryChecklistDialog(
                      context: context,
                      delivery: delivery,
                    );
                    if (context.mounted) {
                      ref.invalidate(
                          deliveryChecklistStatusProvider(delivery.id));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _DeliveryFact(
                  icon: time == null ? Icons.event : Icons.schedule,
                  label:
                      time == null ? 'All day' : DateTimeUtils.formatTime(time),
                ),
                if (delivery.vehicleCount != null)
                  _DeliveryFact(
                    icon: Icons.local_shipping_outlined,
                    label: '${delivery.vehicleCount} vehicles',
                  ),
                if (delivery.palletCount != null)
                  _DeliveryFact(
                    icon: Icons.inventory_2_outlined,
                    label: '${delivery.palletCount} pallets',
                  ),
              ],
            ),
            if (staffNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DeliveryFact(
                  icon: Icons.group_outlined, label: staffNames.join(', ')),
            ],
            if (delivery.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _DeliveryFact(icon: Icons.notes, label: delivery.notes!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openStaffAllocation(BuildContext context, WidgetRef ref) async {
    try {
      final schools = await ref
          .read(schoolsRepositoryProvider)
          .watchSchools(schoolIds: [delivery.schoolId]).first;
      if (!context.mounted) return;
      if (schools.isNotEmpty) {
        context.push(
          '/schools/${delivery.schoolId}/staff-allocation',
          extra: schools.first,
        );
        return;
      }
    } catch (_) {
      if (!context.mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Couldn’t load the school for staff allocation.')),
    );
  }

  Future<void> _deleteDelivery(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete delivery?'),
        content: Text(
          'Delete the delivery for ${delivery.schoolName} on '
          '${DateTimeUtils.formatDate(delivery.date)}? This action can’t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await ref
        .read(deliveriesNotifierProvider.notifier)
        .deleteDelivery(delivery.id);
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content:
            Text(success ? 'Delivery deleted' : 'Couldn’t delete delivery'),
      ),
    );
  }
}

class _DeliveryFact extends StatelessWidget {
  const _DeliveryFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label)),
      ],
    );
  }
}
