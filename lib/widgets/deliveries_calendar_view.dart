import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/delivery.dart';
import '../providers/deliveries_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/pre_delivery_checklist_providers.dart';
import '../providers/schools_providers.dart';
import '../services/date_utils.dart';
import '../app/theme/brand_colors.dart';
import 'pre_delivery_checklist_dialog.dart';

class DeliveriesCalendarView extends ConsumerStatefulWidget {
  const DeliveriesCalendarView({super.key});

  @override
  ConsumerState<DeliveriesCalendarView> createState() =>
      _DeliveriesCalendarViewState();
}

class _DeliveriesCalendarViewState
    extends ConsumerState<DeliveriesCalendarView> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final allDeliveriesAsync = ref.watch(allDeliveriesListProvider);
    final currentStaffAsync = ref.watch(currentStaffProvider);
    final isAdmin = ref.watch(isAdminProvider);

    // Check staff assignment status first
    return currentStaffAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => const Center(child: CircularProgressIndicator()),
      data: (staff) {
        // If not linked and not admin, show link prompt
        if (staff == null && !isAdmin) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.link_off,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Account Not Linked',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your account needs to be linked to a staff member to view deliveries.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.go('/staff-link'),
                    icon: const Icon(Icons.link),
                    label: const Text('Link Account'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/profile'),
                    child: const Text('Go to Profile'),
                  ),
                ],
              ),
            ),
          );
        }

        // User is linked, load deliveries (calendar will show even if empty)
        return allDeliveriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Deliveries',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(allDeliveriesListProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (allDeliveries) {
            return _buildCalendarView(context, allDeliveries);
          },
        );
      },
    );
  }

  Widget _buildCalendarView(BuildContext context, List<Delivery> allDeliveries) {
        // Group deliveries by date and sort by time
        final Map<DateTime, List<Delivery>> deliveriesByDate = {};
        for (final delivery in allDeliveries) {
          final date = DateTime(
            delivery.date.year,
            delivery.date.month,
            delivery.date.day,
          );
          deliveriesByDate.putIfAbsent(date, () => []).add(delivery);
        }

        // Sort deliveries within each date by time
        for (final deliveries in deliveriesByDate.values) {
          deliveries.sort((a, b) {
            // Deliveries with time come before deliveries without time
            if (a.time == null && b.time == null) return 0;
            if (a.time == null) return 1;
            if (b.time == null) return -1;
            return a.time!.compareTo(b.time!);
          });
        }

        // Get deliveries for selected day
        final selectedDayDeliveries = _selectedDay != null
            ? deliveriesByDate[DateTime(
                  _selectedDay!.year,
                  _selectedDay!.month,
                  _selectedDay!.day,
                )] ??
                []
            : [];

        return Column(
          children: [
            Card(
              margin: const EdgeInsets.all(16),
              child: TableCalendar<Delivery>(
                firstDay: DateTime.now().subtract(const Duration(days: 365)),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: _calendarFormat,
                eventLoader: (day) {
                  final normalizedDay = DateTime(day.year, day.month, day.day);
                  return deliveriesByDate[normalizedDay] ?? [];
                },
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                // Custom marker builder to show delivery count
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;

                    final deliveryCount = events.length;
                    return Positioned(
                      bottom: 1,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: BrandColors.kakaPink,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            deliveryCount > 9 ? '9+' : '$deliveryCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Styling
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: BrandColors.kakaGreen.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: BrandColors.kakaBlue,
                    shape: BoxShape.circle,
                  ),
                  markerDecoration: const BoxDecoration(
                    color: BrandColors.kakaPink,
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: const TextStyle(
                    color: BrandColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  selectedTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  weekendTextStyle: const TextStyle(
                    color: BrandColors.textSecondary,
                  ),
                  outsideDaysVisible: false,
                  markerSize: 0, // Hide default markers since we use custom builder
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: true,
                  titleCentered: true,
                  formatButtonShowsNext: false,
                  formatButtonDecoration: BoxDecoration(
                    color: BrandColors.kakaGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  formatButtonTextStyle: const TextStyle(
                    color: BrandColors.kakaGreen,
                    fontWeight: FontWeight.w600,
                  ),
                  titleTextStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  weekendStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: BrandColors.textSecondary,
                  ),
                ),
              ),
            ),

            // Selected day deliveries
            if (_selectedDay != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      DateTimeUtils.formatDate(_selectedDay!),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: BrandColors.kakaPink.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${selectedDayDeliveries.length} ${selectedDayDeliveries.length == 1 ? 'delivery' : 'deliveries'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: BrandColors.kakaPink,
                        ),
                      ),
                    ),
                    if (selectedDayDeliveries.length > 1 &&
                        selectedDayDeliveries.any((d) => d.time != null)) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.timeline,
                        size: 16,
                        color: BrandColors.kakaBlue,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Scheduled',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: BrandColors.kakaBlue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Deliveries list for selected day
            Expanded(
              child: selectedDayDeliveries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _selectedDay == null
                                ? Icons.calendar_today
                                : Icons.local_shipping_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedDay == null
                                ? 'Select a date to view deliveries'
                                : 'No deliveries on this day',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: selectedDayDeliveries.length,
                      separatorBuilder: (context, index) {
                        // Show timeline connector between deliveries
                        if (selectedDayDeliveries.length > 1) {
                          final currentHasTime = selectedDayDeliveries[index].time != null;
                          final nextHasTime = index + 1 < selectedDayDeliveries.length &&
                              selectedDayDeliveries[index + 1].time != null;

                          if (currentHasTime || nextHasTime) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 2,
                                    height: 16,
                                    color: BrandColors.kakaBlue.withValues(alpha: 0.3),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: Colors.grey[300],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                        return const SizedBox(height: 8);
                      },
                      itemBuilder: (context, index) {
                        final delivery = selectedDayDeliveries[index];
                        return _DeliveryCalendarCard(
                          delivery: delivery,
                          showTimelineIndicator: selectedDayDeliveries.length > 1 &&
                              selectedDayDeliveries.any((d) => d.time != null),
                        );
                      },
                    ),
            ),
          ],
        );
  }
}

class _DeliveryCalendarCard extends ConsumerWidget {
  const _DeliveryCalendarCard({
    required this.delivery,
    this.showTimelineIndicator = false,
  });

  final Delivery delivery;
  final bool showTimelineIndicator;

  Future<void> _deleteDelivery(BuildContext context, WidgetRef ref) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Delivery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this delivery?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    delivery.schoolName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateTimeUtils.formatDate(delivery.date),
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 13,
                    ),
                  ),
                  if (delivery.time != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[700]),
                        const SizedBox(width: 4),
                        Text(
                          DateTimeUtils.formatTime(delivery.time!),
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Delete the delivery
    final deliveriesNotifier = ref.read(deliveriesNotifierProvider.notifier);
    final success = await deliveriesNotifier.deleteDelivery(delivery.id);

    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorState = ref.read(deliveriesNotifierProvider);
        final errorMessage = errorState.error?.toString() ?? 'Failed to delete delivery';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTime = delivery.time != null;
    final canEdit = ref.watch(canAssignDeliveriesProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final schoolStaffAsync = ref.watch(schoolStaffProvider(delivery.schoolId));
    final schoolsAsync = ref.watch(schoolsProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        if (showTimelineIndicator) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: hasTime ? BrandColors.kakaBlue : Colors.grey[400],
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (hasTime ? BrandColors.kakaBlue : Colors.grey)
                        .withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasTime
                      ? BrandColors.kakaBlue.withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    onTap: () => context.go('/schools/${delivery.schoolId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Pre-delivery checklist checkbox
                              _buildCheckbox(context, ref),
                              const SizedBox(width: 8),
                              // Time badge
                              if (hasTime)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: BrandColors.kakaBlue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.access_time,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        DateTimeUtils.formatTime(delivery.time!),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.event,
                                        size: 14,
                                        color: Colors.grey[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'All day',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              // Vehicle count badge
                              if (delivery.vehicleCount != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[700],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.local_shipping,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'x${delivery.vehicleCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // Pallet count badge
                              if (delivery.palletCount != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.purple[600],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Symbols.pallet,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'x${delivery.palletCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (canEdit)
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[600]),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 8,
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      context.go('/deliveries/${delivery.id}/edit');
                                    } else if (value == 'delete') {
                                      _deleteDelivery(context, ref);
                                    } else if (value == 'staff') {
                                      schoolsAsync.whenData((schools) {
                                        final school = schools.where((s) => s.id == delivery.schoolId).firstOrNull;
                                        if (school != null) {
                                          context.push('/schools/${delivery.schoolId}/staff-allocation', extra: school);
                                        }
                                      });
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: BrandColors.kakaBlue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(
                                              Icons.edit_outlined,
                                              size: 16,
                                              color: BrandColors.kakaBlue,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'Edit',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: BrandColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: BrandColors.kakaPink.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                              color: BrandColors.kakaPink,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'Delete',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: BrandColors.kakaPink,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isAdmin)
                                      PopupMenuItem(
                                        value: 'staff',
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: BrandColors.kakaGreen.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Icon(
                                                Icons.people_outline,
                                                size: 16,
                                                color: BrandColors.kakaGreen,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text(
                                              'Manage Staff',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: BrandColors.textPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                )
                              else
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            delivery.schoolName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          // Display assigned staff members
                          schoolStaffAsync.when(
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (staffList) {
                              if (staffList.isEmpty) return const SizedBox.shrink();

                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: staffList.map((staff) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: staff.isAdmin
                                            ? BrandColors.kakaPink.withValues(alpha: 0.15)
                                            : staff.isManager
                                                ? BrandColors.kakaBlue.withValues(alpha: 0.15)
                                                : BrandColors.kakaGreen.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            staff.isAdmin
                                                ? Icons.admin_panel_settings
                                                : staff.isManager
                                                    ? Icons.supervisor_account
                                                    : Icons.person,
                                            size: 12,
                                            color: staff.isAdmin
                                                ? BrandColors.kakaPink
                                                : staff.isManager
                                                    ? BrandColors.kakaBlue
                                                    : BrandColors.kakaGreen,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            staff.name,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: staff.isAdmin
                                                  ? BrandColors.kakaPink
                                                  : staff.isManager
                                                      ? BrandColors.kakaBlue
                                                      : BrandColors.kakaGreen,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            },
                          ),
                          if (delivery.notes?.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.note, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      delivery.notes!,
                                      style: TextStyle(color: Colors.grey[700]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the pre-delivery checklist checkbox inline with badges
  Widget _buildCheckbox(BuildContext context, WidgetRef ref) {
    final checklistStatusAsync = ref.watch(deliveryChecklistStatusProvider(delivery.id));

    return checklistStatusAsync.when(
      loading: () => SizedBox(
        width: 28,
        height: 28,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey[400],
          ),
        ),
      ),
      error: (_, __) => InkWell(
        onTap: () => _showChecklistDialog(context, ref),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.withValues(alpha: 0.1),
            border: Border.all(
              color: Colors.grey[400]!,
              width: 2,
            ),
          ),
        ),
      ),
      data: (isComplete) => InkWell(
        onTap: () => _showChecklistDialog(context, ref),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComplete
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.1),
            border: Border.all(
              color: isComplete ? Colors.green : Colors.grey[400]!,
              width: 2,
            ),
          ),
          child: isComplete
              ? const Icon(
                  Icons.check,
                  size: 16,
                  color: Colors.green,
                )
              : null,
        ),
      ),
    );
  }

  Future<void> _showChecklistDialog(BuildContext context, WidgetRef ref) async {
    await showPreDeliveryChecklistDialog(
      context: context,
      ref: ref,
      delivery: delivery,
    );
    // Refresh the status after dialog closes
    ref.invalidate(deliveryChecklistStatusProvider(delivery.id));
  }
}
