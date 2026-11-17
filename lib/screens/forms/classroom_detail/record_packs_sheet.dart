part of '../classroom_detail_screen.dart';

/// Body of the "Record packs" sheet: who it is for, a large editable number
/// with 64 pt − / + buttons, what is left, and "All N delivered". The number
/// is the field draft's `quantity` input, so typing still works and every
/// change is kept as a draft on the device.
class _RecordPacksBody extends StatelessWidget {
  const _RecordPacksBody({
    required this.fields,
    required this.classroomName,
    required this.yearLabel,
    required this.yearWords,
    required this.expected,
  });

  final FieldDraftFields fields;
  final String classroomName;

  /// Year label for the badge; null draws the neutral badge (composite or
  /// unknown year level).
  final String? yearLabel;

  /// The year level in words ("Year 1", "Year 1/2").
  final String? yearWords;
  final int? expected;

  static const _inputId = 'quantity';

  TextEditingController get _controller => fields.controller(_inputId);

  int? get _count => int.tryParse(_controller.text.trim());

  void _set(int value) {
    _controller.value = TextEditingValue(
      text: '$value',
      selection: TextSelection.collapsed(offset: '$value'.length),
    );
    fields.changed();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final enabled = fields.enabled;
    final count = _count;
    final text = _controller.text.trim();
    final expected = this.expected;

    final details = [
      if (yearWords != null) yearWords!,
      expected == null
          ? 'Expected total not set'
          : '${_plural(expected, 'pack')} expected',
    ].join(' · ');

    final String remaining;
    if (count == null || count < 0) {
      remaining = expected == null
          ? 'Enter the packs delivered'
          : '${_plural(expected, 'pack')} expected';
    } else if (expected == null) {
      remaining = '${_plural(count, 'pack')} recorded';
    } else {
      final left = expected - count;
      remaining = left > 0
          ? '${_plural(left, 'pack')} still to deliver'
          : left == 0
              ? 'All packs delivered'
              : '${_plural(-left, 'pack')} more than expected';
    }

    final digits = text.length;
    final numberSize = digits <= 3
        ? 72.0
        : digits <= 5
            ? 52.0
            : 36.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppYearBadge(label: yearLabel ?? ''),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(classroomName,
                      style:
                          AppTypography.headline.copyWith(color: colors.ink)),
                  Text(details,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StepButton(
              icon: AppIcons.remove,
              semanticLabel: 'One fewer pack',
              onPressed: enabled && (count ?? 0) > 0
                  ? () => _set((count ?? 0) - 1)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  // The figure is already very large; letting it grow with
                  // the text scale would push the − / + buttons off screen.
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1,
                    child: TextFormField(
                      key: const ValueKey(_inputId),
                      controller: _controller,
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      validator: (value) => _validateCount(value ?? ''),
                      onChanged: (_) => fields.changed(),
                      style: TextStyle(
                        fontSize: numberSize,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                        color: colors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        hintText: '–',
                        errorMaxLines: 4,
                        errorStyle: AppTypography.footnote
                            .copyWith(color: colors.error),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('packs delivered',
                      textAlign: TextAlign.center,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _StepButton(
              icon: AppIcons.add,
              semanticLabel: 'One more pack',
              onPressed: enabled && (count ?? 0) < 1000000
                  ? () => _set((count ?? -1) + 1)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            remaining,
            textAlign: TextAlign.center,
            style: AppTypography.subheadline.copyWith(color: colors.muted),
          ),
        ),
        if (expected != null) ...[
          const SizedBox(height: 20),
          AppSecondaryButton(
            label: 'All $expected delivered',
            onPressed:
                enabled && count != expected ? () => _set(expected) : null,
          ),
        ],
      ],
    );
  }
}

/// 64 pt round grey − / + button.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      excludeChildSemantics: true,
      child: SizedBox.square(
        dimension: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.fill, shape: BoxShape.circle),
          child: Icon(icon, size: 28, color: colors.ink),
        ),
      ),
    );
  }
}
