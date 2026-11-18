import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/delivery.dart';
import '../models/delivery_visit.dart';
import '../providers/auth_providers.dart';
import '../providers/deliveries_providers.dart';
import '../providers/pre_delivery_checklist_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/visit_signoff_providers.dart';
import '../services/date_utils.dart';
import '../services/offline/connectivity_service.dart';
import 'design/design.dart';
import 'pre_delivery_checklist_dialog.dart';
import 'school_logo.dart';

/// "Tue 17 Nov 2026" — the day line used by the deliveries screens.
String deliveryDayLabel(DateTime date) => DateTimeUtils.formatWeekdayDate(date);

/// "1 visit" / "2 visits".
String deliveryVisitCount(int count) =>
    '$count ${count == 1 ? 'visit' : 'visits'}';

/// The visits of one day.
///
/// Without [calendar] (the Today view) the first visit that is not signed off
/// is a hero card under "Next visit", the other visits still to sign off are
/// compact rows under "Later today" and signed-off visits are compact rows
/// under "Signed off" at the bottom. With a [calendar] the calendar sits above
/// the selected day's visits, all shown as compact rows in time order.
/// [header] (large title, view switcher…) scrolls with the list.
class DeliveryDayList extends ConsumerWidget {
  const DeliveryDayList({
    super.key,
    required this.date,
    required this.deliveries,
    required this.onRetry,
    this.calendar,
    this.header,
  });

  final DateTime date;
  final AsyncValue<List<Delivery>> deliveries;
  final VoidCallback onRetry;
  final Widget? calendar;
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(connectivityStatusProvider).valueOrNull ==
        ConnectivityStatus.offline;
    final today = calendar == null;
    final loaded = deliveries.asData?.value;

    Widget section(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(top: AppTokens.sectionGap - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSectionLabel(label),
              const SizedBox(height: 8),
              child,
            ],
          ),
        );

    final Widget body = deliveries.when(
      skipLoadingOnRefresh: false,
      loading: () => offline
          ? const DeliveryMessage(
              icon: AppIcons.offline,
              title: 'Checking saved deliveries',
              description: 'A connection may be needed to load this date.',
            )
          : const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
      error: (_, __) => DeliveryMessage(
        icon: AppIcons.error,
        title: 'Couldn’t load deliveries',
        description: offline ? 'Reconnect, then try again.' : null,
        action: AppSecondaryButton(
          label: 'Retry',
          icon: AppIcons.retry,
          expand: false,
          onPressed: onRetry,
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return DeliveryMessage(
            icon: AppIcons.deliveries,
            title: offline
                ? 'No saved deliveries for this date'
                : 'No deliveries scheduled',
          );
        }
        // Visit numbers follow the day's time order in every section.
        final numbered = [
          for (var index = 0; index < items.length; index++)
            (delivery: items[index], number: index + 1),
        ];
        if (!today) return _VisitRows(visits: numbered);

        final toSignOff = <_NumberedVisit>[];
        final signedOff = <_NumberedVisit>[];
        for (final visit in numbered) {
          (ref.watch(visitSignedOffProvider(_visitOf(visit.delivery)))
                  ? signedOff
                  : toSignOff)
              .add(visit);
        }
        final next = toSignOff.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (next != null)
              section(
                'Next visit',
                _NextVisitCard(
                  key: ValueKey(next.delivery.id),
                  delivery: next.delivery,
                  visitNumber: next.number,
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: AppTokens.sectionGap - 4),
                child: AppNotice(
                  key: ValueKey('all-visits-signed-off'),
                  icon: AppIcons.complete,
                  message: 'All visits signed off today',
                ),
              ),
            if (toSignOff.length > 1)
              section('Later today', _VisitRows(visits: toSignOff.sublist(1))),
            if (signedOff.isNotEmpty)
              section('Signed off', _VisitRows(visits: signedOff)),
          ],
        );
      },
    );

    final dayLabel = [
      deliveryDayLabel(date),
      if (loaded != null) deliveryVisitCount(loaded.length),
    ].join(' · ');

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: AppInsets.scroll(context),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (header != null) header!,
                  if (calendar != null) ...[
                    const SizedBox(height: 16),
                    calendar!,
                    const SizedBox(height: AppTokens.sectionGap - 4),
                    AppSectionLabel(dayLabel),
                    const SizedBox(height: 8),
                  ],
                  body,
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon, title, optional description and action for empty, error, offline
/// and gated states. Scrolls itself when given a bounded height.
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
    final colors = AppPalette.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: AppIconTile(icon: icon, size: 48)),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.title3.copyWith(color: colors.ink),
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: AppTypography.subheadline.copyWith(color: colors.muted),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
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

/// "9:00 AM" or "All day".
String _visitTime(Delivery delivery) {
  final time = delivery.time;
  return time == null ? 'All day' : DateTimeUtils.formatTime(time);
}

String? _plural(int? count, String noun) =>
    count == null ? null : '$count ${count == 1 ? noun : '${noun}s'}';

List<String> _staffNames(WidgetRef ref, Delivery delivery, bool canEdit) {
  final team = canEdit
      ? ref.watch(schoolStaffProvider(delivery.schoolId)).valueOrNull
      : null;
  return team?.map((staff) => staff.name).toList() ?? delivery.staffNames;
}

typedef _NumberedVisit = ({Delivery delivery, int number});

DeliveryVisit _visitOf(Delivery delivery) =>
    DeliveryVisit(deliveryId: delivery.id, schoolId: delivery.schoolId);

void _openVisit(BuildContext context, Delivery delivery) {
  context.push(
    schoolWorkPath(delivery.schoolId, visit: _visitOf(delivery)),
    extra: delivery,
  );
}

/// The checklist's real status, in words.
({String label, bool complete}) _checklistStatus(AsyncValue<bool> status) =>
    status.when(
      skipLoadingOnRefresh: false,
      data: (complete) => complete
          ? (label: 'Complete', complete: true)
          : (label: 'To complete', complete: false),
      error: (_, __) => (label: 'Status unavailable', complete: false),
      loading: () => (label: 'Checking…', complete: false),
    );

Future<void> _openChecklist(
    BuildContext context, WidgetRef ref, Delivery delivery) async {
  await showPreDeliveryChecklistDialog(context: context, delivery: delivery);
  if (context.mounted) {
    ref.invalidate(deliveryChecklistStatusProvider(delivery.id));
  }
}

/// The next visit of the day: school, facts, instructions, checklist and the
/// "Open visit" action.
class _NextVisitCard extends ConsumerWidget {
  const _NextVisitCard({
    super.key,
    required this.delivery,
    required this.visitNumber,
  });

  final Delivery delivery;
  final int visitNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppPalette.of(context);
    final canEdit = ref.watch(canAssignDeliveriesProvider);
    final staffNames = _staffNames(ref, delivery, canEdit);
    final checklist = _checklistStatus(
        ref.watch(deliveryChecklistStatusProvider(delivery.id)));
    final facts = [
      if (_plural(delivery.vehicleCount, 'vehicle') case final vehicles?)
        (AppIcons.vehiclesMini, vehicles),
      if (_plural(delivery.palletCount, 'pallet') case final pallets?)
        (AppIcons.palletsMini, pallets),
      if (staffNames.isNotEmpty) (AppIcons.staffMini, staffNames.join(', ')),
    ];
    final notes = delivery.notes?.trim();

    return AppPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: SchoolLogoForId(schoolId: delivery.schoolId, size: 48),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_visitTime(delivery)} · Visit $visitNumber',
                      style: AppTypography.footnote.copyWith(
                          color: colors.muted, fontWeight: FontWeight.w600),
                    ),
                    Semantics(
                      header: true,
                      child: Text(
                        delivery.schoolName,
                        style: AppTypography.title2.copyWith(color: colors.ink),
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 8),
                _VisitOptionsButton(
                  delivery: delivery,
                  tooltip: 'Manage delivery',
                  includeChecklist: false,
                ),
              ],
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final (icon, label) in facts)
                  _VisitFact(icon: icon, label: label),
              ],
            ),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            AppNotice(message: notes),
          ],
          const SizedBox(height: 6),
          _ChecklistRow(
            status: checklist.label,
            complete: checklist.complete,
            onTap: () => _openChecklist(context, ref, delivery),
          ),
          const SizedBox(height: 8),
          AppPrimaryButton(
            label: 'Open visit',
            onPressed: () => _openVisit(context, delivery),
          ),
        ],
      ),
    );
  }
}

class _VisitFact extends StatelessWidget {
  const _VisitFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: ExcludeSemantics(
            child: Icon(icon, size: 16, color: colors.muted),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: AppTypography.subheadline.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// "Pre-delivery checklist · To complete ›" — opens the checklist.
class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.status,
    required this.complete,
    required this.onTap,
  });

  final String status;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPressable(
      key: const ValueKey('pre-delivery-checklist-row'),
      onTap: onTap,
      semanticLabel: 'Pre-delivery checklist, $status',
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.minTouchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const AppIconTile(icon: AppIcons.checklist, size: 29),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(
                      'Pre-delivery checklist',
                      style:
                          AppTypography.subheadline.copyWith(color: colors.ink),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (complete) ...[
                          Icon(AppIcons.complete, size: 16, color: colors.ink),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            status,
                            style: AppTypography.subheadline.copyWith(
                              color: colors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.chevron, size: 16, color: colors.chevron),
            ],
          ),
        ),
      ),
    );
  }
}

/// The checklist's real status on a compact row, in words with a 16 pt icon.
({String label, Widget icon}) _rowChecklistStatus(
    BuildContext context, AsyncValue<bool> status) {
  final colors = AppPalette.of(context);
  Widget glyph(IconData icon) => Icon(icon, size: 16, color: colors.muted);
  return status.when(
    skipLoadingOnRefresh: false,
    data: (complete) => complete
        ? (
            label: 'Checklist complete',
            icon: const AppStatusRing(status: AppCompletion.complete, size: 16),
          )
        : (
            label: 'Checklist to complete',
            icon:
                const AppStatusRing(status: AppCompletion.notStarted, size: 16),
          ),
    error: (_, __) =>
        (label: 'Checklist status unavailable', icon: glyph(AppIcons.error)),
    loading: () => (label: 'Checking checklist…', icon: glyph(AppIcons.timer)),
  );
}

/// Compact visit rows in one grouped card.
class _VisitRows extends StatelessWidget {
  const _VisitRows({required this.visits});

  final List<_NumberedVisit> visits;

  @override
  Widget build(BuildContext context) {
    return AppGroupedList(
      separatorIndent: 57,
      children: [
        for (final visit in visits)
          _VisitRow(
            key: ValueKey(visit.delivery.id),
            delivery: visit.delivery,
            visitNumber: visit.number,
          ),
      ],
    );
  }
}

/// A small status under a row's subtitle: 16 pt icon and words that wrap.
class _RowStatus extends StatelessWidget {
  const _RowStatus({super.key, required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final style = AppTypography.footnote.copyWith(color: colors.muted);
    final lineHeight = MediaQuery.textScalerOf(context)
        .scale(style.fontSize! * (style.height ?? 1.3));
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Centred on the first line of the words.
          SizedBox(
            height: lineHeight < 16 ? 16 : lineHeight,
            child: Center(child: ExcludeSemantics(child: icon)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: style)),
        ],
      ),
    );
  }
}

/// School name, "1:30 PM · Visit 2 · 2 pallets", staff and instructions, the
/// pre-delivery checklist status (or "Signed off"), a visit options menu
/// (checklist and management) and a chevron. The row opens the visit.
class _VisitRow extends ConsumerWidget {
  const _VisitRow({
    super.key,
    required this.delivery,
    required this.visitNumber,
  });

  final Delivery delivery;
  final int visitNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppPalette.of(context);
    final canEdit = ref.watch(canAssignDeliveriesProvider);
    final staffNames = _staffNames(ref, delivery, canEdit);
    final notes = delivery.notes?.trim();
    final meta = [
      _visitTime(delivery),
      'Visit $visitNumber',
      if (_plural(delivery.vehicleCount, 'vehicle') case final vehicles?)
        vehicles,
      if (_plural(delivery.palletCount, 'pallet') case final pallets?) pallets,
    ].join(' · ');
    final secondary = AppTypography.subheadline.copyWith(color: colors.muted);
    final signedOff = ref.watch(visitSignedOffProvider(_visitOf(delivery)));
    final checklist = signedOff
        ? null
        : _rowChecklistStatus(
            context, ref.watch(deliveryChecklistStatusProvider(delivery.id)));

    return AppPressable(
      onTap: () => _openVisit(context, delivery),
      pressedColor: colors.fill,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              ExcludeSemantics(
                child: SchoolLogoForId(schoolId: delivery.schoolId, size: 29),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delivery.schoolName,
                      style: AppTypography.body.copyWith(color: colors.ink),
                    ),
                    Text(meta, style: secondary),
                    if (staffNames.isNotEmpty)
                      Text(staffNames.join(', '), style: secondary),
                    if (notes != null && notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(AppIcons.info,
                                  size: 15, color: colors.muted),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(notes,
                                  style: secondary.copyWith(color: colors.ink)),
                            ),
                          ],
                        ),
                      ),
                    if (signedOff)
                      _RowStatus(
                        key: const ValueKey('visit-row-signed-off'),
                        icon: Icon(AppIcons.complete,
                            size: 16, color: colors.ink),
                        label: 'Signed off',
                      )
                    else if (checklist != null)
                      _RowStatus(
                        key: const ValueKey('visit-row-checklist'),
                        icon: checklist.icon,
                        label: checklist.label,
                      ),
                  ],
                ),
              ),
              _VisitOptionsButton(
                delivery: delivery,
                tooltip: 'Visit options for ${delivery.schoolName}',
                includeChecklist: true,
              ),
              ExcludeSemantics(
                child: Icon(AppIcons.chevron, size: 16, color: colors.chevron),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Options for one visit: its pre-delivery checklist (rows only) and, for the
/// roles that have it, edit / delete / manage staff.
class _VisitOptionsButton extends ConsumerWidget {
  const _VisitOptionsButton({
    required this.delivery,
    required this.tooltip,
    required this.includeChecklist,
  });

  final Delivery delivery;
  final String tooltip;
  final bool includeChecklist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final canEdit = ref.watch(canAssignDeliveriesProvider);
    final checklist = includeChecklist
        ? _checklistStatus(
            ref.watch(deliveryChecklistStatusProvider(delivery.id)))
        : null;

    PopupMenuItem<String> item(String value, IconData icon, String label,
            {bool destructive = false}) =>
        appMenuItem(context, value, label,
            icon: icon, destructive: destructive);

    return AppMenuButton<String>(
      tooltip: tooltip,
      itemBuilder: (context) => [
        if (checklist != null)
          item('checklist', AppIcons.checklist,
              'Pre-delivery checklist · ${checklist.label}'),
        if (canEdit) item('edit', AppIcons.edit, 'Edit'),
        if (isAdmin) item('staff', AppIcons.people, 'Manage staff'),
        if (isAdmin)
          item('delete', AppIcons.delete, 'Delete', destructive: true),
      ],
      onSelected: (value) {
        switch (value) {
          case 'checklist':
            _openChecklist(context, ref, delivery);
          case 'edit':
            context.go('/deliveries/${delivery.id}/edit');
          case 'delete':
            _deleteDelivery(context, ref, delivery);
          case 'staff':
            _openStaffAllocation(context, ref, delivery);
        }
      },
    );
  }
}

Future<void> _openStaffAllocation(
    BuildContext context, WidgetRef ref, Delivery delivery) async {
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

Future<void> _deleteDelivery(
    BuildContext context, WidgetRef ref, Delivery delivery) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
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
            style: appDestructiveButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final success = await ref
      .read(deliveriesNotifierProvider.notifier)
      .deleteDelivery(delivery.id);
  if (!messenger.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(success ? 'Delivery deleted' : 'Couldn’t delete delivery'),
    ),
  );
}
