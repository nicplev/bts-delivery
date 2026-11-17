import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/delivery_visit.dart';
import '../models/offline/saved_edit.dart';
import '../providers/auth_providers.dart';
import '../providers/saved_edit_providers.dart';
import '../services/offline/saved_edit_recovery.dart';
import 'design/design.dart';

/// Compact notice above the tab bar for edits retained on this device: amber
/// with "Review" when an edit needs a decision, neutral glass when work is
/// only waiting.
class SavedEditsBanner extends ConsumerWidget {
  const SavedEditsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    if (uid == null) return const SizedBox.shrink();
    final state = ref.watch(savedEditsProvider);
    final edits = state.valueOrNull
            ?.where((entry) => entry.intent.ownerUid == uid)
            .toList() ??
        const <SavedEdit>[];
    final count = edits.length;
    if (count == 0 && !state.hasError) return const SizedBox.shrink();
    final toReview = edits.where((edit) => _needsReview(edit.state)).length;
    final warning = !state.hasError && toReview > 0;
    final message = state.hasError
        ? 'Could not read saved edits on this device.'
        : toReview > 0
            ? toReview == 1
                ? '1 edit to review'
                : '$toReview edits to review'
            : count == 1
                ? '1 saved edit on this device'
                : '$count saved edits on this device';
    return _CompactNotice(
      warning: warning,
      icon: state.hasError
          ? AppIcons.error
          : warning
              ? AppIcons.warning
              : AppIcons.savedOnDevice,
      message: message,
      action: state.hasError
          ? AppSecondaryButton(
              label: 'Try again',
              expand: false,
              large: false,
              onPressed: () => ref.invalidate(savedEditsProvider),
            )
          : AppSecondaryButton(
              label: 'Review',
              expand: false,
              large: false,
              onPressed: () => _showSavedEdits(context, uid),
            ),
    );
  }
}

/// The notice body: the action drops below the message on narrow screens or
/// with large text.
class _CompactNotice extends StatelessWidget {
  const _CompactNotice({
    required this.warning,
    required this.icon,
    required this.message,
    required this.action,
  });

  final bool warning;
  final IconData icon;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final ink = warning ? colors.warningInk : colors.ink;
    final stacked = MediaQuery.sizeOf(context).width < 375 ||
        MediaQuery.textScalerOf(context).scale(17) > 21;
    final text = Text(
      message,
      style: AppTypography.subheadline
          .copyWith(color: ink, fontWeight: FontWeight.w600),
    );
    final glyph = Icon(icon, size: 20, color: warning ? ink : colors.muted);
    final Widget content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Row(
                  children: [
                    glyph,
                    const SizedBox(width: 10),
                    Expanded(child: text),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Align(alignment: AlignmentDirectional.centerEnd, child: action),
            ],
          )
        : Row(
            children: [
              glyph,
              const SizedBox(width: 10),
              Expanded(child: text),
              const SizedBox(width: 8),
              action,
            ],
          );
    const radius = BorderRadius.all(Radius.circular(26));
    const padding = EdgeInsets.fromLTRB(14, 4, 4, 4);
    final Widget shell = warning
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: colors.warningTint,
              borderRadius: radius,
              boxShadow: colors.highContrast ? null : AppTokens.glassShadow,
              border: colors.highContrast
                  ? Border.all(color: colors.outline, width: 1.5)
                  : null,
            ),
            child: Padding(padding: padding, child: content),
          )
        : AppGlass(borderRadius: radius, padding: padding, child: content);
    return Semantics(
      container: true,
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.minTouchTarget),
        child: shell,
      ),
    );
  }
}

bool _needsReview(SavedEditState state) =>
    state == SavedEditState.review || state == SavedEditState.rejected;

Future<void> _showSavedEdits(BuildContext context, String uid) async {
  final router = GoRouter.of(context);
  final location = await showAppGlassSheet<String>(
    context: context,
    title: 'Saved edits',
    contentPadding: EdgeInsets.zero,
    builder: (_) => _SavedEditsList(ownerUid: uid),
  );
  if (location != null && context.mounted) router.push(location);
}

class _SavedEditsList extends ConsumerWidget {
  const _SavedEditsList({required this.ownerUid});

  final String ownerUid;

  static const _padding = EdgeInsets.fromLTRB(
      AppTokens.gutter, 0, AppTokens.gutter, AppTokens.sectionGap);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authStateProvider).valueOrNull?.uid != ownerUid) {
      return const Padding(
        padding: _padding,
        child: AppNotice(
          message: 'The signed-in account changed.',
          icon: AppIcons.person,
        ),
      );
    }
    final state = ref.watch(savedEditsProvider);
    final colors = AppPalette.of(context);
    return state.when(
      loading: () => const Padding(
        padding: _padding,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: _padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppNotice(
              message: 'Could not read saved edits on this device.',
              icon: AppIcons.error,
            ),
            const SizedBox(height: 12),
            AppSecondaryButton(
              label: 'Try loading saved edits again',
              icon: AppIcons.retry,
              onPressed: () => ref.invalidate(savedEditsProvider),
            ),
          ],
        ),
      ),
      data: (entries) {
        final edits = entries
            .where((entry) => entry.intent.ownerUid == ownerUid)
            .toList();
        if (edits.isEmpty) {
          return const Padding(
            padding: _padding,
            child: AppNotice(
              message: 'No saved edits to review',
              icon: AppIcons.completeOutline,
            ),
          );
        }
        return ListView(
          shrinkWrap: true,
          padding: _padding,
          children: [
            for (final edit in edits) ...[
              _SavedEditCard(
                key: ValueKey(edit.intent.id),
                edit: edit,
                onOpen: () => _openEdit(context, edit),
              ),
              const SizedBox(height: 12),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Saved work stays on this device until the server confirms it.',
                style: AppTypography.footnote.copyWith(color: colors.muted),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEdit(BuildContext context, SavedEdit edit) async {
    final location = await showDialog<String>(
      context: context,
      builder: (_) => _EditReviewDialog(edit: edit),
    );
    if (location != null &&
        context.mounted &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(location);
    }
  }
}

/// One saved edit: amber icon tile and heading when it needs a decision,
/// neutral when it is only waiting.
class _SavedEditCard extends StatelessWidget {
  const _SavedEditCard({super.key, required this.edit, required this.onOpen});

  final SavedEdit edit;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final intent = edit.intent;
    final review = _needsReview(edit.state);
    final icon = _kindIcon(intent.kind);
    final date = DateFormat.MMMd().add_jm().format(intent.capturedAt.toLocal());
    final status = _status(edit.state);
    return AppPanel(
      padding: const EdgeInsets.all(20),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              review
                  ? AppIconTile.warning(icon: icon)
                  : AppIconTile(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review ? 'Edit to review' : status,
                      style: AppTypography.footnote.copyWith(
                        fontWeight: FontWeight.w600,
                        color: review ? colors.warningInk : colors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      intent.itemLabel ?? intent.title,
                      style: AppTypography.headline.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      review ? '$status · $date' : date,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
              if (!review) ...[
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child:
                      Icon(AppIcons.chevron, size: 16, color: colors.chevron),
                ),
              ],
            ],
          ),
          if (review) ...[
            const SizedBox(height: 16),
            AppSecondaryButton(label: 'Review change', onPressed: onOpen),
          ],
        ],
      ),
    );
  }
}

IconData _kindIcon(SavedEditKind kind) => switch (kind) {
      SavedEditKind.classroomName ||
      SavedEditKind.classroomStatus =>
        AppIcons.classroom,
      SavedEditKind.noteCreate ||
      SavedEditKind.noteContent ||
      SavedEditKind.noteDelete =>
        AppIcons.notes,
      SavedEditKind.packTotal => AppIcons.packs,
      SavedEditKind.consumableCount => AppIcons.consumables,
      SavedEditKind.checklist => AppIcons.checklist,
    };

String _status(SavedEditState state) => switch (state) {
      SavedEditState.waiting => 'Saved on this device',
      SavedEditState.queued => 'Last seen in the Firestore queue',
      SavedEditState.review => 'Check current values',
      SavedEditState.rejected => 'Server rejected the save',
      SavedEditState.matched => 'Server values matched at last check',
      SavedEditState.acknowledged || SavedEditState.dismissed => 'Reviewed',
    };

class _EditReviewDialog extends ConsumerStatefulWidget {
  const _EditReviewDialog({required this.edit});

  final SavedEdit edit;

  @override
  ConsumerState<_EditReviewDialog> createState() => _EditReviewDialogState();
}

class _EditReviewDialogState extends ConsumerState<_EditReviewDialog> {
  SavedEditComparison? _comparison;
  String? _error;
  bool _busy = true;
  EditIntent get _intent => widget.edit.intent;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final result = await ref.read(savedEditRecoveryProvider).compare(_intent);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _comparison = result;
    });
  }

  Future<void> _complete({required bool retry}) async {
    final comparison = _comparison;
    if (comparison == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final recovery = ref.read(savedEditRecoveryProvider);
    final result = retry
        ? await recovery.retry(_intent, comparison)
        : await recovery.clear(_intent, comparison);
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _error = result.errorOrNull;
        _comparison = null;
      });
      await _loadCurrent();
    }
  }

  String _display(EditIntent intent, Map<String, Object?> values) {
    final details = switch (intent.kind) {
      SavedEditKind.classroomName => ['name'],
      SavedEditKind.classroomStatus => [
          'completionStatus',
          'actualPacksDelivered'
        ],
      SavedEditKind.noteCreate ||
      SavedEditKind.noteContent ||
      SavedEditKind.noteDelete =>
        ['content'],
      SavedEditKind.packTotal => ['total'],
      SavedEditKind.consumableCount => ['actualQuantityDelivered'],
      SavedEditKind.checklist => ['isCompleted'],
    };
    return details.map((field) {
      final value = values[field];
      if (field == 'completionStatus') {
        return switch (value) {
          'complete' => 'Complete',
          'incomplete' => 'Incomplete',
          'notAttended' => 'Not attended',
          _ => 'No value',
        };
      }
      if (field == 'isCompleted') {
        return value == true ? 'Checked' : 'Unchecked';
      }
      if (field == 'actualPacksDelivered') {
        return 'Actual packs: ${value ?? 'No value'}';
      }
      return value?.toString() ?? 'No value';
    }).join('\n');
  }

  /// Opaque grey value box; the heading carries the meaning, not colour.
  Widget _valuesPanel(String title, String values) {
    final colors = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceQuiet,
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        border: colors.highContrast ? Border.all(color: colors.outline) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTypography.footnote
                  .copyWith(fontWeight: FontWeight.w600, color: colors.muted),
            ),
            const SizedBox(height: 4),
            SelectableText(
              values,
              style: AppTypography.body.copyWith(color: colors.ink),
            ),
          ],
        ),
      ),
    );
  }

  void _openLocation() {
    final classroom =
        _intent.yearLevelId != null && _intent.classroomId != null;
    Navigator.of(context).pop(schoolWorkPath(
      _intent.schoolId,
      visit: _intent.visit,
      suffix: classroom
          ? '/year/${Uri.encodeComponent(_intent.yearLevelId!)}'
              '/classrooms/${Uri.encodeComponent(_intent.classroomId!)}'
          : '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authStateProvider).valueOrNull?.uid != _intent.ownerUid) {
      return AlertDialog(
        content: const Text('The signed-in account changed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      );
    }
    final colors = AppPalette.of(context);
    final comparison = _comparison;
    final current = comparison?.current;
    final review = _needsReview(widget.edit.state);
    final body = AppTypography.subheadline.copyWith(color: colors.ink);
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            review ? 'Edit to review' : _status(widget.edit.state),
            style: AppTypography.footnote.copyWith(
              fontWeight: FontWeight.w600,
              color: review ? colors.warningInk : colors.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(_intent.itemLabel ?? _intent.title),
        ],
      ),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _valuesPanel(
            _intent.deletesDocument
                ? 'Note selected for deletion'
                : 'Your saved values',
            _display(_intent, _intent.values),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (comparison != null) Text(comparison.message, style: body),
          if (current?.exists == true) ...[
            const SizedBox(height: 12),
            _valuesPanel(
                'Current server values', _display(_intent, current!.fields)),
          ],
          if (comparison?.canRetry == true &&
              _intent.kind == SavedEditKind.packTotal) ...[
            const SizedBox(height: 12),
            Text(
              'Retry saves this count at its original time. Any later count stays current.',
              style: body,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppNotice(message: _error!, icon: AppIcons.error),
          ],
          const SizedBox(height: 12),
          AppSecondaryButton(
            label:
                _intent.classroomId == null ? 'Open visit' : 'Open classroom',
            icon: _intent.classroomId == null
                ? AppIcons.school
                : AppIcons.classroom,
            large: false,
            onPressed: _busy ? null : _openLocation,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
        if (!_busy && comparison?.canResolve != true)
          TextButton(
            onPressed: () {
              setState(() => _busy = true);
              _loadCurrent();
            },
            child: const Text('Check again'),
          ),
        if (!_busy && comparison?.canResolve == true)
          TextButton(
            onPressed: () => _complete(retry: false),
            child: Text(current!.matches(_intent)
                ? 'Clear saved copy'
                : 'Keep server values'),
          ),
        if (!_busy && comparison?.canRetry == true)
          FilledButton(
            onPressed: () => _complete(retry: true),
            child: Text(_intent.deletesDocument
                ? 'Delete current note'
                : 'Retry saved edit'),
          ),
      ],
    );
  }
}
