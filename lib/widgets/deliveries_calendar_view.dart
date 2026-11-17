import 'dart:math' as math;

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
    this.header,
  });

  final DateTime firstDay;
  final DateTime lastDay;
  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarFormat format;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final ValueChanged<CalendarFormat> onFormatChanged;

  /// Scrolls above the calendar (the screen's large title and switcher).
  final Widget? header;

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
    final textScaler = MediaQuery.textScalerOf(context);
    final compactHeader =
        MediaQuery.sizeOf(context).width <= 360 || textScaler.scale(12) > 17;
    final colors = AppPalette.of(context);
    const formats = {
      CalendarFormat.month: 'Month',
      CalendarFormat.twoWeeks: '2 weeks',
      CalendarFormat.week: 'Week',
    };
    final dayText = AppTypography.body.copyWith(color: colors.ink);
    final weekdayText = AppTypography.footnote
        .copyWith(color: colors.muted, fontWeight: FontWeight.w600);
    const circle = BoxDecoration(shape: BoxShape.circle);

    return DeliveryDayList(
      header: header,
      date: displayedDay,
      deliveries: deliveries.whenData(
        (_) => [...deliveriesOn(displayedDay)]..sort(compareDeliveryTimes),
      ),
      onRetry: () => ref.invalidate(provider),
      calendar: AppPanel(
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
              pageAnimationEnabled: !MediaQuery.disableAnimationsOf(context),
              // Only horizontal swipes change the page, so a vertical scroll
              // of the screen never collapses the month.
              availableGestures: AvailableGestures.horizontalSwipe,
              daysOfWeekHeight: textScaler.scale(18) + 4,
              rowHeight: math.max(52, textScaler.scale(22) + 30),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                // The day circle sits a little high in its cell so the
                // delivery dots below never touch it.
                cellMargin: const EdgeInsets.fromLTRB(7, 2, 7, 14),
                defaultTextStyle: dayText,
                weekendTextStyle: dayText,
                disabledTextStyle: dayText.copyWith(color: colors.inactive),
                selectedDecoration: circle.copyWith(color: colors.action),
                selectedTextStyle: dayText.copyWith(
                  color: colors.onAction,
                  fontWeight: FontWeight.w600,
                ),
                todayDecoration: circle.copyWith(
                  border: Border.all(color: colors.ink, width: 1.5),
                ),
                todayTextStyle: dayText.copyWith(fontWeight: FontWeight.w600),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: weekdayText,
                weekendStyle: weekdayText,
              ),
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonVisible: !compactHeader,
                formatButtonShowsNext: false,
                leftChevronIcon: Icon(AppIcons.previousPage,
                    size: 20, color: colors.ink, semanticLabel: 'Previous'),
                rightChevronIcon: Icon(AppIcons.nextPage,
                    size: 20, color: colors.ink, semanticLabel: 'Next'),
                leftChevronPadding: const EdgeInsets.all(12),
                rightChevronPadding: const EdgeInsets.all(12),
                leftChevronMargin: EdgeInsets.zero,
                rightChevronMargin: EdgeInsets.zero,
                titleTextStyle:
                    AppTypography.headline.copyWith(color: colors.ink),
                formatButtonTextStyle: AppTypography.footnote.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w600,
                ),
                formatButtonDecoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(AppTokens.pillRadius),
                ),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  return Positioned(
                    bottom: 2,
                    child: _DeliveryDots(count: events.length),
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
                        icon: AppIcons.chevronDown,
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

/// Up to three small ink dots under a day that has deliveries.
class _DeliveryDots extends StatelessWidget {
  const _DeliveryDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.of(context).ink;
    return Semantics(
      label: '$count ${count == 1 ? 'delivery' : 'deliveries'}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < (count > 3 ? 3 : count); i++)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
        ],
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
