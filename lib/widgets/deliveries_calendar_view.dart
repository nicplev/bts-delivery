import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/delivery.dart';
import '../providers/deliveries_providers.dart';
import '../repositories/deliveries_repository.dart';
import 'delivery_day_list.dart';

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

    return DeliveryDayList(
      date: displayedDay,
      deliveries: deliveries.whenData(
        (_) => [...deliveriesOn(displayedDay)]..sort(compareDeliveryTimes),
      ),
      onRetry: () => ref.invalidate(provider),
      calendar: Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: TableCalendar<Delivery>(
          firstDay: firstDay,
          lastDay: lastDay,
          focusedDay: focusedDay,
          selectedDayPredicate: (date) => isSameDay(displayedDay, date),
          calendarFormat: format,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          onDaySelected: onDaySelected,
          onPageChanged: onPageChanged,
          onFormatChanged: onFormatChanged,
          eventLoader: deliveriesOn,
          calendarStyle: const CalendarStyle(outsideDaysVisible: false),
          headerStyle: const HeaderStyle(
            titleCentered: true,
            formatButtonShowsNext: false,
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              return Positioned(
                bottom: 1,
                child: Badge(
                  label: Text(events.length > 9 ? '9+' : '${events.length}'),
                ),
              );
            },
          ),
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
