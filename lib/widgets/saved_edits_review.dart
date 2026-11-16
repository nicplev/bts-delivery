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

class SavedEditsBanner extends ConsumerWidget {
  const SavedEditsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    if (uid == null) return const SizedBox.shrink();
    final state = ref.watch(savedEditsProvider);
    final count = state.valueOrNull
            ?.where((entry) => entry.intent.ownerUid == uid)
            .length ??
        0;
    if (count == 0 && !state.hasError) return const SizedBox.shrink();
    return MaterialBanner(
      backgroundColor: state.hasError ? AppTone.pink.tint : AppTone.blue.tint,
      dividerColor: AppTokens.outline,
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
      leadingPadding: const EdgeInsetsDirectional.only(end: 8),
      leading: AppIconTile(
        icon: state.hasError ? Icons.info_outline : Icons.edit_note_outlined,
        size: 32,
        tone: state.hasError ? AppTone.pink : AppTone.blue,
      ),
      content: Text(state.hasError
          ? 'Could not read saved edits on this device.'
          : count == 1
              ? '1 saved edit on this device'
              : '$count saved edits on this device'),
      actions: [
        if (state.hasError)
          TextButton(
            onPressed: () => ref.invalidate(savedEditsProvider),
            child: const Text('Try again'),
          )
        else
          TextButton(
            onPressed: () => _showSavedEdits(context, uid),
            child: const Text('Review'),
          ),
      ],
    );
  }
}

Future<void> _showSavedEdits(BuildContext context, String uid) async {
  final router = GoRouter.of(context);
  final location = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.8,
      child: _SavedEditsList(ownerUid: uid),
    ),
  );
  if (location != null && context.mounted) router.push(location);
}

class _SavedEditsList extends ConsumerWidget {
  const _SavedEditsList({required this.ownerUid});

  final String ownerUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authStateProvider).valueOrNull?.uid != ownerUid) {
      return const Center(child: Text('The signed-in account changed.'));
    }
    final state = ref.watch(savedEditsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding:
              EdgeInsets.symmetric(horizontal: AppTokens.gutter, vertical: 8),
          child: AppSectionHeading(title: 'Saved edits'),
        ),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(savedEditsProvider),
                child: const Text('Try loading saved edits again'),
              ),
            ),
            data: (entries) {
              final edits = entries
                  .where((entry) => entry.intent.ownerUid == ownerUid)
                  .toList();
              if (edits.isEmpty) {
                return const Center(child: Text('No saved edits to review'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 8,
                    AppTokens.gutter, AppTokens.sectionGap),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: edits.length,
                itemBuilder: (context, index) {
                  final edit = edits[index];
                  final date = DateFormat.MMMd()
                      .add_jm()
                      .format(edit.intent.capturedAt.toLocal());
                  return AppPanel(
                    key: ValueKey(edit.intent.id),
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(edit.intent.itemLabel ?? edit.intent.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          AppStatusPill(
                            label: _status(edit.state),
                            tone: _tone(edit.state),
                          ),
                          const SizedBox(height: 4),
                          Text(date),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final location = await showDialog<String>(
                          context: context,
                          builder: (_) => _EditReviewDialog(edit: edit),
                        );
                        if (location != null &&
                            context.mounted &&
                            ModalRoute.of(context)?.isCurrent == true) {
                          Navigator.of(context).pop(location);
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  AppTone _tone(SavedEditState state) => switch (state) {
        SavedEditState.rejected => AppTone.pink,
        SavedEditState.review => AppTone.yellow,
        SavedEditState.matched => AppTone.green,
        SavedEditState.waiting || SavedEditState.queued => AppTone.blue,
        _ => AppTone.neutral,
      };

  String _status(SavedEditState state) => switch (state) {
        SavedEditState.waiting => 'Saved on this device',
        SavedEditState.queued => 'Last seen in the Firestore queue',
        SavedEditState.review => 'Check current values',
        SavedEditState.rejected => 'Server rejected the save',
        SavedEditState.matched => 'Server values matched at last check',
        SavedEditState.acknowledged || SavedEditState.dismissed => 'Reviewed',
      };
}

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

  Widget _valuesPanel(String title, String values, AppTone tone) => AppPanel(
        tone: tone,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(values),
          ],
        ),
      );

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
    final comparison = _comparison;
    final current = comparison?.current;
    return AlertDialog(
      title: Text(_intent.itemLabel ?? _intent.title),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _valuesPanel(
            _intent.deletesDocument
                ? 'Note selected for deletion'
                : 'Your saved values',
            _display(_intent, _intent.values),
            AppTone.blue,
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (comparison != null) Text(comparison.message),
          if (current?.exists == true) ...[
            const SizedBox(height: 12),
            _valuesPanel('Current server values',
                _display(_intent, current!.fields), AppTone.neutral),
          ],
          if (comparison?.canRetry == true &&
              _intent.kind == SavedEditKind.packTotal) ...[
            const SizedBox(height: 12),
            const Text(
                'Retry saves this count at its original time. Any later count stays current.'),
          ],
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _openLocation,
            child: Text(
                _intent.classroomId == null ? 'Open visit' : 'Open classroom'),
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
