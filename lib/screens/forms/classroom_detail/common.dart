part of '../classroom_detail_screen.dart';

typedef _ClassroomKey = ({
  String schoolId,
  String yearLevelId,
  String classroomId,
});

/// Where a classroom's records live (and which visit they belong to).
class _Room {
  const _Room({
    required this.schoolId,
    required this.yearLevelId,
    required this.classroomId,
    required this.deliveryId,
  });

  final String schoolId;
  final String yearLevelId;
  final String classroomId;
  final String? deliveryId;

  _ClassroomKey get packKey => (
        schoolId: schoolId,
        yearLevelId: yearLevelId,
        classroomId: classroomId,
      );

  ({
    String schoolId,
    String yearLevelId,
    String classroomId,
    String? deliveryId
  }) get photosKey => (
        schoolId: schoolId,
        yearLevelId: yearLevelId,
        classroomId: classroomId,
        deliveryId: deliveryId,
      );

  FieldDraftTarget draftTarget(String form, {String? entityId}) =>
      FieldDraftTarget(
        schoolId: schoolId,
        deliveryId: deliveryId,
        yearLevelId: yearLevelId,
        classroomId: classroomId,
        form: form,
        entityId: entityId,
      );
}

String? _validateCount(String value, {bool optional = false}) {
  if (value.trim().isEmpty) {
    return optional ? null : 'Enter a quantity.';
  }
  final count = int.tryParse(value.trim());
  if (count == null || count < 0 || count > 1000000) {
    return 'Enter a whole number from 0 to 1,000,000.';
  }
  return null;
}

/// "17 Nov 2026, 10:40 AM" (the app-wide date-time format).
String _formatDate(DateTime date) => DateTimeUtils.formatDateTime(date);

String _plural(int count, String one, [String? many]) =>
    '$count ${count == 1 ? one : many ?? '${one}s'}';

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

/// A section of the classroom work surface: label (with an optional add
/// action) above an opaque card, 24 pt below the previous section.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.child,
    this.action,
    this.caption,
  });

  final String label;
  final Widget child;

  /// Usually an [_AddButton].
  final Widget? action;

  /// Optional line between the label and the card (e.g. "1 waiting to upload").
  final Widget? caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionLabel(label, trailing: action),
          if (caption != null) ...[const SizedBox(height: 4), caption!],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Compact grey capsule ("Add", "Add photo") for a section's add action.
class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.label,
    required this.onPressed,
    this.icon = AppIcons.add,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final button = AppSecondaryButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      expand: false,
      large: false,
    );
    if (semanticLabel == null) return button;
    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      onTap: onPressed,
      child: button,
    );
  }
}

/// A message row inside a section card (loading or error state) with an
/// optional action below it.
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.title,
    this.subtitle,
    this.isError = false,
    this.loading = false,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool isError;
  final bool loading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final Widget? leading = loading
        ? const SizedBox.square(
            dimension: 29,
            child: Padding(
              padding: EdgeInsets.all(5),
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          )
        : isError
            ? SizedBox.square(
                dimension: 29,
                child: Icon(AppIcons.error, color: colors.error, size: 22),
              )
            : null;
    final row = AppListRow(
      leading: leading,
      title: title,
      subtitle: subtitle,
      titleStyle: isError
          ? AppTypography.body
              .copyWith(color: colors.error, fontWeight: FontWeight.w600)
          : null,
    );
    if (trailing == null) return row;
    // The action sits under the message so long or large text never has to
    // share the line with it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: EdgeInsets.fromLTRB(leading == null ? 16 : 57, 0, 16, 12),
          child: Align(
              alignment: AlignmentDirectional.centerStart, child: trailing),
        ),
      ],
    );
  }
}

/// Error-red filled button for a destructive confirmation.
Widget _destructiveButton(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
}) {
  return FilledButton(
    onPressed: onPressed,
    style: appDestructiveButtonStyle(context),
    child: Text(label),
  );
}

/// Truthful save state for this classroom's edits and photo uploads. Shown
/// only when this device holds something not yet confirmed by the server;
/// the screen never learns of a server acknowledgement, so it never claims
/// "Saved to server".
class _SavedStateLine extends ConsumerWidget {
  const _SavedStateLine({required this.room, required this.offline});

  final _Room room;
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edits = (ref.watch(savedEditsProvider).valueOrNull ?? const [])
        .where((edit) =>
            edit.intent.schoolId == room.schoolId &&
            edit.intent.yearLevelId == room.yearLevelId &&
            edit.intent.classroomId == room.classroomId &&
            edit.intent.deliveryId == room.deliveryId)
        .toList();
    final uploads = ref.watch(evidenceUploadsProvider).valueOrNull?.items ??
        const <EvidenceUpload>[];
    final pendingPhotos = uploads.where((item) =>
        item.kind == EvidenceKind.photo &&
        item.schoolId == room.schoolId &&
        item.yearLevelId == room.yearLevelId &&
        item.classroomId == room.classroomId &&
        item.deliveryId == room.deliveryId);
    final review = edits
        .where((edit) =>
            edit.state == SavedEditState.review ||
            edit.state == SavedEditState.rejected)
        .length;
    final waiting = edits.any((edit) =>
            edit.state == SavedEditState.waiting ||
            edit.state == SavedEditState.queued) ||
        pendingPhotos.isNotEmpty;

    final Widget line;
    if (review > 0) {
      line = AppStatusLine(
        icon: AppIcons.warning,
        iconColor: AppPalette.of(context).warningInk,
        text: review == 1
            ? '1 saved change needs review'
            : '$review saved changes need review',
      );
    } else if (waiting) {
      line = AppStatusLine(
        icon: AppIcons.savedOnDevice,
        text: offline
            ? 'Saved on this device · uploads resume when you reconnect'
            : 'Saved on this device · Sync pending',
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.sectionGap),
      child: Semantics(liveRegion: true, child: line),
    );
  }
}

typedef _InlineAction = ({
  String label,
  IconData icon,
  VoidCallback? onPressed,
});

/// A compact row of 44 pt grey capsules side by side under an item; they
/// stack full width only at large text sizes. Labels wrap between words,
/// never inside one.
class _InlineActions extends StatelessWidget {
  const _InlineActions({required this.actions});

  final List<_InlineAction> actions;

  @override
  Widget build(BuildContext context) {
    final stack = MediaQuery.textScalerOf(context).scale(15) > 20;
    final buttons = [
      for (final action in actions)
        _CompactCapsule(
          label: action.label,
          icon: action.icon,
          onPressed: action.onPressed,
        ),
    ];
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            buttons[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

/// A 44 pt grey capsule with a small icon and a 15 pt semibold ink label.
class _CompactCapsule extends StatelessWidget {
  const _CompactCapsule({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final enabled = onPressed != null;
    final ink = enabled ? colors.ink : colors.ink.withValues(alpha: 0.35);
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.minTouchTarget),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(AppTokens.pillRadius),
            border:
                colors.highContrast ? Border.all(color: colors.outline) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: ink),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
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
