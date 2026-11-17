import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery.dart';
import '../models/pre_delivery_checklist_item.dart';
import '../models/pre_delivery_completion.dart';
import '../providers/pre_delivery_checklist_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'field_draft_dialog.dart';
import 'design/design.dart';

/// Opens a glass sheet immediately and keeps the checklist responsive as data
/// loads. Resolves to `true` when it is closed with every item checked.
Future<bool> showPreDeliveryChecklistDialog({
  required BuildContext context,
  required Delivery delivery,
}) async {
  final result = await showAppGlassSheet<bool>(
    context: context,
    title: 'Pre-delivery checklist',
    builder: (_) => _PreDeliveryChecklistDialog(delivery: delivery),
  );
  return result ?? false;
}

class _PreDeliveryChecklistDialog extends ConsumerStatefulWidget {
  const _PreDeliveryChecklistDialog({required this.delivery});

  final Delivery delivery;

  @override
  ConsumerState<_PreDeliveryChecklistDialog> createState() =>
      _PreDeliveryChecklistDialogState();
}

class _PreDeliveryChecklistDialogState
    extends ConsumerState<_PreDeliveryChecklistDialog> {
  final _saving = <String>{};
  final _feedback = <String, ({String message, bool error})>{};

  Future<void> _toggle(PreDeliveryChecklistItem item, bool value) async {
    if (_saving.contains(item.id)) return;
    setState(() {
      _saving.add(item.id);
      _feedback.remove(item.id);
    });

    try {
      final result = await ref
          .read(preDeliveryChecklistNotifierProvider.notifier)
          .saveCompletion(
            schoolId: widget.delivery.schoolId,
            deliveryId: widget.delivery.id,
            itemId: item.id,
            isCompleted: value,
            itemLabel: item.title,
          );
      if (!mounted) return;
      setState(() {
        _feedback[item.id] = result.when(
          success: (status) => (
            message: fieldEditFeedback('Checklist change', status),
            error: false
          ),
          failure: (message, _) => (message: message, error: true),
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedback[item.id] = (
            message: 'Couldn’t save this checklist item.',
            error: true,
          );
        });
      }
    } finally {
      if (mounted) setState(() => _saving.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(activePreDeliveryChecklistItemsProvider);
    final completionProvider = deliveryCompletionsProvider(widget.delivery.id);
    final completions = ref.watch(completionProvider);
    final offline = ref.watch(connectivityStatusProvider).valueOrNull ==
        ConnectivityStatus.offline;
    final done = completions.valueOrNull
            ?.where((completion) => completion.isCompleted)
            .map((completion) => completion.itemId)
            .toSet() ??
        const <String>{};
    final allChecked =
        items.valueOrNull?.every((item) => done.contains(item.id)) == true &&
            !items.hasError &&
            !completions.hasError &&
            completions.hasValue;
    final failed = items.hasError || completions.hasError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: _buildChecklist(items, completions, offline, done),
          ),
        ),
        const SizedBox(height: 16),
        if (failed) ...[
          AppPrimaryButton(
            label: 'Retry',
            icon: AppIcons.retry,
            onPressed: () {
              if (items.hasError) {
                ref.invalidate(activePreDeliveryChecklistItemsProvider);
              }
              if (completions.hasError) ref.invalidate(completionProvider);
            },
          ),
          const SizedBox(height: 8),
        ],
        if (allChecked)
          AppPrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(true),
          )
        else
          AppSecondaryButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(false),
          ),
      ],
    );
  }

  Widget _buildChecklist(
    AsyncValue<List<PreDeliveryChecklistItem>> items,
    AsyncValue<List<PreDeliveryCompletion>> completions,
    bool offline,
    Set<String> done,
  ) {
    final colors = AppPalette.of(context);
    Widget note(String message, IconData icon) => Semantics(
          liveRegion: true,
          child: AppNotice(message: message, icon: icon),
        );

    if (items.hasError || completions.hasError) {
      return note(
        offline
            ? 'Couldn’t load the checklist on this device.'
            : 'Couldn’t load the checklist. Try again.',
        AppIcons.error,
      );
    }
    final active = items.valueOrNull;
    if (active == null || !completions.hasValue) {
      return note(
        offline ? 'Checking saved checklist items…' : 'Loading checklist…',
        offline ? AppIcons.offline : AppIcons.timer,
      );
    }
    if (active.isEmpty) {
      return note(
        offline
            ? 'No checklist items saved on this device.'
            : 'No checklist items.',
        AppIcons.info,
      );
    }
    final completed = active.where((item) => done.contains(item.id)).length;
    final progress = '$completed of ${active.length} checked'
        '${offline ? ' on this device' : ''}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.delivery.schoolName,
          style: AppTypography.headline.copyWith(color: colors.ink),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            AppStatusRing.fromCounts(
              done: completed,
              total: active.length,
              semanticLabel: completed == active.length
                  ? 'Complete'
                  : completed == 0
                      ? 'Not started'
                      : 'Partial',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  progress,
                  style: AppTypography.subheadline.copyWith(color: colors.ink),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppProgressBar(
          value: completed / active.length,
          semanticLabel: 'Checklist items checked',
        ),
        const SizedBox(height: 14),
        AppGroupedList(
          children: [
            for (final item in active)
              CheckboxListTile(
                onChanged: _saving.contains(item.id)
                    ? null
                    : (value) => _toggle(item, value ?? false),
                value: done.contains(item.id),
                title: Text(item.title),
                subtitle: _buildItemSubtitle(item),
                controlAffinity: ListTileControlAffinity.leading,
                // The app's round check: an empty grey ring that becomes a
                // solid ink check-circle; the whole row toggles it.
                checkboxShape: const CircleBorder(),
                checkboxScaleFactor: 1.3,
                side: BorderSide(color: colors.inactive, width: 1.5),
                activeColor: colors.action,
                checkColor: colors.onAction,
              ),
          ],
        ),
      ],
    );
  }

  Widget? _buildItemSubtitle(PreDeliveryChecklistItem item) {
    final feedback = _feedback[item.id];
    final saving = _saving.contains(item.id);
    if (item.subtitle == null && feedback == null && !saving) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.subtitle != null) Text(item.subtitle!),
        if (saving || feedback != null)
          Semantics(
            liveRegion: true,
            child: Text(
              saving ? 'Saving…' : feedback!.message,
              style: feedback?.error == true
                  ? TextStyle(color: AppPalette.of(context).error)
                  : null,
            ),
          ),
      ],
    );
  }
}
