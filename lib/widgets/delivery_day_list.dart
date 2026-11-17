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
import 'design/design.dart';
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

    final loaded = deliveries.asData?.value;
    final showSummary = calendar == null && loaded != null && loaded.isNotEmpty;
    final text = Theme.of(context).textTheme;
    final localizations = MaterialLocalizations.of(context);
    final day = calendar == null
        ? localizations.formatMediumDate(date)
        : localizations.formatFullDate(date);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: CustomScrollView(
          slivers: [
            if (calendar != null) SliverToBoxAdapter(child: calendar),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.gutter,
                12,
                AppTokens.gutter,
                14,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(day, style: text.titleMedium),
                    ),
                    if (showSummary) ...[
                      const SizedBox(height: 4),
                      Text(_deliverySummary(loaded), style: text.bodySmall),
                    ],
                  ],
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
                  action: TextButton(
                      onPressed: onRetry, child: const Text('Retry')),
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
                  padding: const EdgeInsets.fromLTRB(
                      AppTokens.gutter, 0, AppTokens.gutter, 88),
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
        ),
      ),
    );
  }
}

String _deliverySummary(List<Delivery> deliveries) {
  final total = deliveries.length;
  final schools =
      deliveries.map((delivery) => delivery.schoolId).toSet().length;
  return '$total ${total == 1 ? 'delivery' : 'deliveries'} · '
      '$schools ${schools == 1 ? 'school' : 'schools'}';
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
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconTile(icon: icon, size: 56),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
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
    return LayoutBuilder(
      builder: (context, constraints) => constraints.hasBoundedHeight
          ? SingleChildScrollView(child: content)
          : content,
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
    final (checklistIcon, checklistLabel, checklistTone) = checklist.when(
      skipLoadingOnRefresh: false,
      data: (complete) => complete
          ? (Icons.task_alt, 'Checklist complete', AppTone.green)
          : (Icons.checklist, 'Checklist incomplete', AppTone.blue),
      error: (_, __) =>
          (Icons.error_outline, 'Checklist status unavailable', AppTone.pink),
      loading: () =>
          (Icons.checklist, 'Checking checklist status', AppTone.blue),
    );
    final time = delivery.time;
    final vehicles = delivery.vehicleCount;
    final pallets = delivery.palletCount;
    final metadata = [
      time == null ? 'All day' : DateTimeUtils.formatTime(time),
      if (vehicles != null)
        '$vehicles ${vehicles == 1 ? 'vehicle' : 'vehicles'}',
      if (pallets != null) '$pallets ${pallets == 1 ? 'pallet' : 'pallets'}',
    ];
    final text = Theme.of(context).textTheme;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(delivery.schoolName, style: text.titleLarge),
                    ),
                    const SizedBox(height: 4),
                    Text(metadata.join(' · '), style: text.bodySmall),
                  ],
                ),
              ),
              if (canEdit)
                PopupMenuButton<String>(
                  tooltip: 'Manage delivery',
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (isAdmin)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    if (isAdmin)
                      const PopupMenuItem(
                          value: 'staff', child: Text('Manage staff')),
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
          if (staffNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DeliveryFact(
                icon: Icons.group_outlined, label: staffNames.join(', ')),
          ],
          if (delivery.notes?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _DeliveryFact(
              icon: Icons.notes_outlined,
              label: delivery.notes!,
              isInstruction: true,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Open school'),
                onPressed: () => context.push(
                  schoolWorkPath(
                    delivery.schoolId,
                    visit: DeliveryVisit(
                        deliveryId: delivery.id, schoolId: delivery.schoolId),
                  ),
                  extra: delivery,
                ),
              ),
              TextButton.icon(
                icon: Icon(checklistIcon, size: 18),
                label: Text(checklistLabel),
                style: TextButton.styleFrom(
                  foregroundColor: checklistTone.inkFor(context),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
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
        ],
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
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
  const _DeliveryFact({
    required this.icon,
    required this.label,
    this.isInstruction = false,
  });

  final IconData icon;
  final String label;
  final bool isInstruction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppPalette.of(context).muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: isInstruction ? text.bodyMedium : text.bodySmall,
          ),
        ),
      ],
    );
  }
}
