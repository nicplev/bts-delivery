import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/delivery.dart';
import '../providers/deliveries_providers.dart';
import '../repositories/deliveries_repository.dart';
import 'delivery_day_list.dart';
import 'design/design.dart';

class DeliveriesCalendarView extends ConsumerWidget {
  const DeliveriesCalendarView({
    super.key,
    required this.firstDay,
    required this.lastDay,
    required this.focusedDay,
    required this.selectedDay,
    required this.format,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.onFormatChanged,
  });

  final DateTime firstDay;
  final DateTime lastDay;
  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarFormat format;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final ValueChanged<CalendarFormat> onFormatChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = visibleDeliveryDates(
      firstDay: firstDay,
      focusedDay: focusedDay,
      format: format,
    );
    final provider = calendarDeliveriesProvider(range);
    final deliveries = ref.watch(provider);
    final deliveriesByDate = <DateTime, List<Delivery>>{};
    for (final delivery in deliveries.asData?.value ?? <Delivery>[]) {
      final date = delivery.date.toLocal();
      deliveriesByDate
          .putIfAbsent(
            DateTime(date.year, date.month, date.day),
            () => [],
          )
          .add(delivery);
    }
    List<Delivery> deliveriesOn(DateTime date) =>
        deliveriesByDate[DateTime(date.year, date.month, date.day)] ?? const [];

    final selectionVisible = includesDeliveryDate(range, selectedDay);
    final displayedDay = selectionVisible ? selectedDay : focusedDay;
    final compactHeader = MediaQuery.sizeOf(context).width <= 360 ||
        MediaQuery.textScalerOf(context).scale(12) > 17;
    const formats = {
      CalendarFormat.month: 'Month',
      CalendarFormat.twoWeeks: '2 weeks',
      CalendarFormat.week: 'Week',
    };

    return DeliveryDayList(
      date: displayedDay,
      deliveries: deliveries.whenData(
        (_) => [...deliveriesOn(displayedDay)]..sort(compareDeliveryTimes),
      ),
      onRetry: () => ref.invalidate(provider),
      calendar: AppPanel(
        margin:
            const EdgeInsets.fromLTRB(AppTokens.gutter, 8, AppTokens.gutter, 0),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            TableCalendar<Delivery>(
              firstDay: firstDay,
              lastDay: lastDay,
              focusedDay: focusedDay,
              selectedDayPredicate: (date) => isSameDay(displayedDay, date),
              calendarFormat: format,
              availableCalendarFormats: formats,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              onFormatChanged: onFormatChanged,
              eventLoader: deliveriesOn,
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                defaultTextStyle: const TextStyle(color: AppTokens.ink),
                weekendTextStyle: const TextStyle(color: AppTokens.muted),
                selectedDecoration: BoxDecoration(
                  color: AppTone.blue.accent,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(
                  color: AppTokens.ink,
                  fontWeight: FontWeight.w700,
                ),
                todayDecoration: BoxDecoration(
                  color: AppTone.green.tint,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: AppTone.green.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                    color: AppTokens.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 11),
                weekendStyle: TextStyle(
                    color: AppTokens.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 11),
              ),
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonVisible: !compactHeader,
                formatButtonShowsNext: false,
                leftChevronPadding: const EdgeInsets.all(10),
                rightChevronPadding: const EdgeInsets.all(10),
                leftChevronMargin: EdgeInsets.zero,
                rightChevronMargin: EdgeInsets.zero,
                titleTextStyle: Theme.of(context).textTheme.titleMedium!,
                formatButtonTextStyle: TextStyle(
                  color: AppTone.blue.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                formatButtonDecoration: BoxDecoration(
                  color: AppTone.blue.tint,
                  borderRadius: BorderRadius.circular(AppTokens.pillRadius),
                ),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  return Positioned(
                    bottom: 1,
                    child: Badge(
                      label:
                          Text(events.length > 9 ? '9+' : '${events.length}'),
                    ),
                  );
                },
              ),
            ),
            if (compactHeader)
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<CalendarFormat>(
                  tooltip: 'Calendar view',
                  initialValue: format,
                  onSelected: onFormatChanged,
                  itemBuilder: (context) => [
                    for (final entry in formats.entries)
                      PopupMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      alignment: Alignment.centerRight,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: AppStatusPill(
                        label: formats[format]!,
                        icon: Icons.expand_more,
                        tone: AppTone.blue,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

DeliveryDateRange visibleDeliveryDates({
  required DateTime firstDay,
  required DateTime focusedDay,
  required CalendarFormat format,
}) {
  if (format == CalendarFormat.month) {
    return (
      start: DateTime(focusedDay.year, focusedDay.month),
      end: DateTime(focusedDay.year, focusedDay.month + 1),
    );
  }

  final daysPerPage = format == CalendarFormat.week ? 7 : 14;
  final anchor = DateTime.utc(
    firstDay.year,
    firstDay.month,
    firstDay.day - (firstDay.weekday % 7),
  );
  final focus = DateTime.utc(focusedDay.year, focusedDay.month, focusedDay.day);
  // TableCalendar aligns every week and two-week page to the first visible week.
  final page = focus.difference(anchor).inDays ~/ daysPerPage;
  final first = anchor.add(Duration(days: page * daysPerPage));
  return (
    start: DateTime(first.year, first.month, first.day),
    end: DateTime(first.year, first.month, first.day + daysPerPage),
  );
}

bool includesDeliveryDate(DeliveryDateRange range, DateTime date) {
  // TableCalendar supplies UTC date labels. Reinterpret the calendar day in
  // local time, matching the midnight boundaries used by the Firestore query.
  final day = DateTime(date.year, date.month, date.day);
  return !day.isBefore(range.start) && day.isBefore(range.end);
}
