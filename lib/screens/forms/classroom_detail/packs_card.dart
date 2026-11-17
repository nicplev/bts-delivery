part of '../classroom_detail_screen.dart';

String _statusLabel(ClassroomCompletionStatus status) => switch (status) {
      ClassroomCompletionStatus.notAttended => 'Not attended',
      ClassroomCompletionStatus.incomplete => 'Incomplete',
      ClassroomCompletionStatus.complete => 'Complete',
    };

/// The packs card: delivery status pill, the recorded number (never shown as
/// 0 when nothing was recorded), the ink progress bar and what is left, plus
/// the pack delivery status choice.
class _PacksCard extends StatelessWidget {
  const _PacksCard({
    required this.classroomsAsync,
    required this.classroom,
    required this.packTotalAsync,
    required this.showRecorded,
    required this.onStatusSelected,
  });

  final AsyncValue<List<Classroom>> classroomsAsync;
  final Classroom? classroom;
  final AsyncValue<PackTotal?> packTotalAsync;

  /// Recorded packs belong to a visit; outside a visit only the expected
  /// total is shown.
  final bool showRecorded;
  final ValueChanged<ClassroomCompletionStatus> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final expected = packTotalAsync.valueOrNull;
    final room = classroom;
    final actual = room?.actualPacksDelivered;

    // The headline figure and the words beside it.
    final String figure;
    final String? caption;
    var figureIsNumber = false;
    if (!showRecorded) {
      if (expected != null) {
        figure = '${expected.total}';
        figureIsNumber = true;
        caption = expected.total == 1 ? 'pack expected' : 'packs expected';
      } else {
        figure = packTotalAsync.isLoading
            ? 'Loading…'
            : packTotalAsync.hasError
                ? 'Unavailable'
                : 'Not set';
        caption = null;
      }
    } else if (room == null) {
      figure = classroomsAsync.isLoading ? 'Loading…' : 'Unavailable';
      caption = null;
    } else if (actual == null) {
      figure = 'Unrecorded';
      caption = expected == null
          ? null
          : '${_plural(expected.total, 'pack')} expected';
    } else {
      figure = '$actual';
      figureIsNumber = true;
      caption = expected == null ? 'recorded' : 'of ${expected.total} recorded';
    }

    final children = <Widget>[
      // Wraps (rather than squeezing the label) when the text is large.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          const AppSectionLabel('Packs'),
          if (showRecorded && room != null)
            AppStatusPill(label: _statusLabel(room.completionStatus)),
        ],
      ),
      const SizedBox(height: 8),
      Semantics(
        container: true,
        label: [
          showRecorded ? 'Recorded packs' : 'Expected packs',
          figure,
          if (caption != null) caption,
        ].join(', '),
        excludeSemantics: true,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          children: [
            Text(
              figure,
              style: figureIsNumber
                  ? AppTypography.largeTitle.copyWith(
                      fontSize: 56,
                      height: 60 / 56,
                      letterSpacing: -0.5,
                      color: colors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )
                  : AppTypography.largeTitle.copyWith(color: colors.ink),
            ),
            if (caption != null)
              Padding(
                padding: EdgeInsets.only(bottom: figureIsNumber ? 8 : 5),
                child: Text(
                  caption,
                  style: AppTypography.title3.copyWith(
                      fontWeight: FontWeight.w400, color: colors.muted),
                ),
              ),
          ],
        ),
      ),
    ];

    if (showRecorded && actual != null && expected != null) {
      final left = expected.total - actual;
      children.addAll([
        const SizedBox(height: 16),
        if (expected.total > 0) ...[
          AppProgressBar(
            value: actual / expected.total,
            semanticLabel: 'Packs recorded',
          ),
          const SizedBox(height: 10),
        ],
        Text(
          left > 0
              ? '${_plural(left, 'pack')} still to deliver'
              : left == 0
                  ? 'All packs delivered'
                  : '${_plural(-left, 'pack')} more than expected',
          style: AppTypography.subheadline.copyWith(color: colors.muted),
        ),
      ]);
    }

    // Expected total: loading, unavailable, not set, or when it was updated.
    final expectedNote = packTotalAsync.when<Widget?>(
      loading: () => figure == 'Loading…'
          ? null
          : const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Expected packs unavailable',
          style: AppTypography.subheadline
              .copyWith(color: colors.error, fontWeight: FontWeight.w600),
        ),
      ),
      data: (total) => total == null
          ? (showRecorded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Expected total not set',
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted)),
                )
              : null)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Expected total updated ${_formatDate(total.createdAt)}',
                style: AppTypography.footnote.copyWith(color: colors.muted),
              ),
            ),
    );
    if (expectedNote != null) children.add(expectedNote);

    if (showRecorded && room != null) {
      children.addAll([
        const SizedBox(height: 16),
        Divider(height: 1, thickness: 1, color: colors.separator),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(
            'Pack delivery status',
            style: AppTypography.footnote
                .copyWith(fontWeight: FontWeight.w600, color: colors.muted),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in ClassroomCompletionStatus.values)
              _StatusChoice(
                label: _statusLabel(status),
                icon: switch (status) {
                  ClassroomCompletionStatus.notAttended =>
                    HeroiconsOutline.minusCircle,
                  ClassroomCompletionStatus.incomplete => AppIcons.packs,
                  ClassroomCompletionStatus.complete => AppIcons.check,
                },
                selected: room.completionStatus == status,
                onTap: () => onStatusSelected(status),
              ),
          ],
        ),
      ]);
    }

    return AppPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// One pack delivery status option: grey capsule, ink when selected.
class _StatusChoice extends StatelessWidget {
  const _StatusChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final ink = selected ? colors.onAction : colors.ink;
    return AppPressable(
      onTap: onTap,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.minTouchTarget),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? colors.action : colors.fill,
            borderRadius: BorderRadius.circular(AppTokens.pillRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? AppIcons.complete : icon, size: 18, color: ink),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: AppTypography.subheadline
                        .copyWith(fontWeight: FontWeight.w600, color: ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
