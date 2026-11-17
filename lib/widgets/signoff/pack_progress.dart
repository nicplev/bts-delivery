part of '../signoff_tab.dart';

/// Display-only summary of one classroom for the sign-off review.
class _RoomProgress {
  const _RoomProgress({
    required this.year,
    required this.room,
    required this.expected,
    required this.recorded,
    required this.status,
    required this.note,
  });

  final YearLevel year;
  final Classroom room;

  /// Expected packs; `null` when no pack total is set.
  final int? expected;
  final int recorded;

  /// Completion as the review has always shown it: a classroom marked
  /// complete with consumables short counts as incomplete.
  final ClassroomCompletionStatus status;

  /// First classroom note, shown as the row's context ("Rest due next visit").
  final String? note;

  bool get complete => status == ClassroomCompletionStatus.complete;

  int get outstanding => math.max(0, (expected ?? 0) - recorded);

  String get statusWords => switch (status) {
        ClassroomCompletionStatus.complete => 'Complete',
        ClassroomCompletionStatus.incomplete => 'Incomplete',
        ClassroomCompletionStatus.notAttended => 'Not attended',
      };

  String get counts =>
      expected == null ? '$recorded recorded' : '$recorded of $expected';
}

class _PackProgress {
  const _PackProgress({
    required this.rooms,
    required this.loading,
    required this.unavailable,
  });

  final List<_RoomProgress> rooms;
  final bool loading;
  final bool unavailable;

  int get expected => rooms.fold(0, (sum, room) => sum + (room.expected ?? 0));
  int get recorded => rooms.fold(0, (sum, room) => sum + room.recorded);
  int get outstanding => rooms.fold(0, (sum, room) => sum + room.outstanding);
  int get outstandingRooms =>
      rooms.where((room) => room.outstanding > 0).length;
  bool get known => !loading && !unavailable;
}

String _count(int value, String one, [String? many]) =>
    '$value ${value == 1 ? one : many ?? '${one}s'}';

String _outstandingMessage(int packs, int rooms) =>
    '${_count(packs, 'pack')} outstanding in ${_count(rooms, 'classroom')}';

/// Reads the same classroom providers the breakdown shows and sums the packs
/// recorded against the packs expected. Nothing here writes.
_PackProgress _watchPackProgress(WidgetRef ref, String schoolId) {
  final years = ref.watch(yearLevelsProvider(schoolId));
  var loading = years.isLoading;
  var unavailable = years.hasError;
  final rooms = <_RoomProgress>[];
  for (final year in years.valueOrNull ?? <YearLevel>[]) {
    final classrooms = ref.watch(classroomsProvider(
      (schoolId: schoolId, yearLevelId: year.id),
    ));
    loading = loading || classrooms.isLoading;
    unavailable = unavailable || classrooms.hasError;
    for (final room in classrooms.valueOrNull ?? <Classroom>[]) {
      final scope = (
        schoolId: schoolId,
        yearLevelId: year.id,
        classroomId: room.id,
      );
      final total = ref.watch(packTotalProvider(scope));
      final consumables = ref.watch(classroomConsumablesProvider(scope));
      final notes = ref.watch(classroomNotesProvider(scope)).valueOrNull;
      loading = loading || total.isLoading || consumables.isLoading;
      unavailable = unavailable || total.hasError || consumables.hasError;
      final expected = total.valueOrNull?.total;
      final allConsumables = (consumables.valueOrNull ?? const <Consumable>[])
          .every((item) => item.actualQuantityDelivered == item.quantity);
      final actual = room.actualPacksDelivered;
      final recorded = switch (room.completionStatus) {
        ClassroomCompletionStatus.notAttended => 0,
        ClassroomCompletionStatus.incomplete => actual ?? 0,
        ClassroomCompletionStatus.complete => actual ?? expected ?? 0,
      };
      final status = switch (room.completionStatus) {
        ClassroomCompletionStatus.complete when !allConsumables =>
          ClassroomCompletionStatus.incomplete,
        final value => value,
      };
      final note = notes?.firstOrNull?.content.trim();
      rooms.add(_RoomProgress(
        year: year,
        room: room,
        expected: expected,
        recorded: recorded,
        status: status,
        note: note == null || note.isEmpty ? null : note,
      ));
    }
  }
  return _PackProgress(
      rooms: rooms, loading: loading, unavailable: unavailable);
}

/// "151 of 174 packs recorded" with the ink progress bar and the amber
/// outstanding notice. [compact] is the capture screen's single-line form.
class _PackSummaryCard extends StatelessWidget {
  const _PackSummaryCard({
    required this.progress,
    this.compact = false,
    this.onRefresh,
  });

  final _PackProgress progress;
  final bool compact;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final expected = progress.expected;
    final recorded = progress.recorded;
    final Widget headline;
    if (progress.unavailable) {
      headline = Text('Pack total unavailable',
          style: AppTypography.headline.copyWith(color: colors.ink));
    } else if (progress.loading) {
      headline = Text('Loading…',
          style: AppTypography.headline.copyWith(color: colors.muted));
    } else if (progress.rooms.isEmpty || expected == 0) {
      headline = Text(
        progress.rooms.isEmpty ? 'No classrooms found' : 'No pack total set',
        style: AppTypography.headline.copyWith(color: colors.ink),
      );
    } else if (compact) {
      headline = Text('$recorded of $expected packs recorded',
          style: AppTypography.headline.copyWith(color: colors.ink));
    } else {
      headline = Semantics(
        label: '$recorded of $expected packs recorded',
        excludeSemantics: true,
        child: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              '$recorded',
              style: AppTypography.largeTitle.copyWith(
                fontSize: 28,
                height: 34 / 28,
                color: colors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('of $expected packs recorded',
                  style: AppTypography.body.copyWith(color: colors.muted)),
            ),
          ],
        ),
      );
    }
    final refresh = onRefresh;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: headline),
              if (refresh != null)
                IconButton(
                  onPressed: refresh,
                  tooltip: 'Refresh',
                  constraints: const BoxConstraints.tightFor(
                    width: AppTokens.minTouchTarget,
                    height: AppTokens.minTouchTarget,
                  ),
                  style: IconButton.styleFrom(backgroundColor: colors.fill),
                  icon: Icon(AppIcons.retry, size: 20, color: colors.ink),
                ),
            ],
          ),
          if (!compact && progress.known && expected > 0) ...[
            const SizedBox(height: 10),
            AppProgressBar(
              value: recorded / expected,
              semanticLabel: 'Packs recorded',
            ),
          ],
          if (progress.known && progress.outstanding > 0) ...[
            const SizedBox(height: 14),
            AppNotice.warning(
              message: _outstandingMessage(
                  progress.outstanding, progress.outstandingRooms),
            ),
          ],
        ],
      ),
    );
  }
}

/// A classroom that still needs attention: year badge, name, year in words
/// with the note or status, and "13 of 24". The count moves under the text at
/// large text sizes instead of squeezing the name.
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.room});

  final _RoomProgress room;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(17) > 26;
    final firstLine = (room.note ?? room.statusWords).split('\n').first;
    final detail =
        firstLine.length > 80 ? '${firstLine.substring(0, 79)}…' : firstLine;
    final count = Text(
      room.counts,
      style: AppTypography.headline.copyWith(
        color: colors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Semantics(
      container: true,
      label: '${room.room.name}, ${room.year.label}, ${room.statusWords}, '
          '${room.expected == null ? '${room.recorded} packs recorded' : '${room.recorded} of ${room.expected} packs'}'
          '${room.note == null ? '' : ', note: $detail'}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              AppYearBadge(label: room.year.label),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(room.room.name,
                        style: AppTypography.body.copyWith(color: colors.ink)),
                    Text(
                      '${room.year.label} · $detail',
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted),
                    ),
                    if (largeText) ...[const SizedBox(height: 2), count],
                  ],
                ),
              ),
              if (!largeText) ...[const SizedBox(width: 12), count],
            ],
          ),
        ),
      ),
    );
  }
}
