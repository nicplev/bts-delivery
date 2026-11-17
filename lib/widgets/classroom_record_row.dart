import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/school.dart';
import '../providers/schools_providers.dart';
import 'design/design.dart';

/// Words for the year level as the school wrote it ("Year 1", "Specialist").
String yearLevelWords(String label) =>
    label.trim().isEmpty ? 'Year level' : label.trim();

/// The pack line of a classroom row, e.g. "13 of 24 packs".
///
/// During a visit it reports what was recorded against the expected total;
/// outside a visit (school template) it reports the expected total only. The
/// loading / unavailable / not-set wording is kept honest: no number is shown
/// that the app does not know.
String classroomPackLine({
  required Classroom classroom,
  required AsyncValue<PackTotal?> packTotal,
  required bool isVisit,
}) {
  return packTotal.when(
    loading: () => 'Loading pack total…',
    error: (_, __) => 'Pack total unavailable',
    data: (total) {
      final expected = total?.total;
      if (!isVisit) {
        return expected == null
            ? 'Pack total: Not set'
            : '$expected expected packs';
      }
      final actual = classroom.actualPacksDelivered;
      if (expected == null) {
        return switch (classroom.completionStatus) {
          ClassroomCompletionStatus.complete =>
            'Complete · Pack total: Not set',
          ClassroomCompletionStatus.incomplete => actual == null
              ? 'Unrecorded · Pack total: Not set'
              : '$actual packs recorded · Pack total: Not set',
          ClassroomCompletionStatus.notAttended =>
            'Not started · Pack total: Not set',
        };
      }
      return switch (classroom.completionStatus) {
        ClassroomCompletionStatus.complete => '$expected of $expected packs',
        ClassroomCompletionStatus.incomplete => actual == null
            ? '$expected expected packs · Unrecorded'
            : '$actual of $expected packs',
        ClassroomCompletionStatus.notAttended => '0 of $expected packs',
      };
    },
  );
}

/// Status ring for a classroom's recorded state (visit only).
AppStatusRing classroomStatusRing(Classroom classroom, PackTotal? total) {
  switch (classroom.completionStatus) {
    case ClassroomCompletionStatus.complete:
      return const AppStatusRing(status: AppCompletion.complete);
    case ClassroomCompletionStatus.notAttended:
      return const AppStatusRing(status: AppCompletion.notStarted);
    case ClassroomCompletionStatus.incomplete:
      final expected = total?.total;
      final actual = classroom.actualPacksDelivered;
      final progress = expected != null && expected > 0 && actual != null
          ? (actual / expected).clamp(0.05, 0.95)
          : 0.5;
      return AppStatusRing(status: AppCompletion.partial, progress: progress);
  }
}

/// One classroom row: year badge, classroom name, "Year 1 · 13 of 24 packs",
/// status ring (during a visit) and chevron. Watches the classroom's existing
/// `packTotalProvider` stream.
class ClassroomRecordRow extends ConsumerWidget {
  const ClassroomRecordRow({
    super.key,
    required this.schoolId,
    required this.yearLevelId,
    required this.yearLevelLabel,
    required this.classroom,
    required this.isVisit,
    required this.onTap,
    this.action,
  });

  final String schoolId;
  final String yearLevelId;
  final String yearLevelLabel;
  final Classroom classroom;
  final bool isVisit;
  final VoidCallback onTap;

  /// Optional trailing control (e.g. a classroom options button).
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packTotal = ref.watch(packTotalProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));
    final line = classroomPackLine(
      classroom: classroom,
      packTotal: packTotal,
      isVisit: isVisit,
    );
    final ring =
        isVisit ? classroomStatusRing(classroom, packTotal.valueOrNull) : null;
    final trailing = switch ((ring, action)) {
      (null, null) => null,
      (final Widget r, null) => r,
      (null, final Widget a) => a,
      (final Widget r, final Widget a) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [r, const SizedBox(width: 4), a],
        ),
    };
    return AppListRow(
      leading: AppYearBadge(label: yearLevelLabel),
      title: classroom.name,
      subtitle: '${yearLevelWords(yearLevelLabel)} · $line',
      trailing: trailing,
      onTap: onTap,
    );
  }
}
