import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery.dart';
import '../models/pre_delivery_checklist_item.dart';
import '../models/pre_delivery_completion.dart';
import '../providers/pre_delivery_checklist_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'field_draft_dialog.dart';
import 'design/design.dart';

/// Opens immediately and keeps the checklist responsive as data loads.
Future<bool> showPreDeliveryChecklistDialog({
  required BuildContext context,
  required Delivery delivery,
}) async {
  final result = await showDialog<bool>(
    context: context,
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

    return AlertDialog(
      scrollable: true,
      title: const Text('Pre-delivery checklist'),
      content: _buildChecklist(items, completions, offline, done),
      actions: [
        if (items.hasError || completions.hasError)
          TextButton(
            onPressed: () {
              if (items.hasError) {
                ref.invalidate(activePreDeliveryChecklistItemsProvider);
              }
              if (completions.hasError) ref.invalidate(completionProvider);
            },
            child: const Text('Retry'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(allChecked),
          child: Text(allChecked ? 'Done' : 'Close'),
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
    if (items.hasError || completions.hasError) {
      return Text(offline
          ? 'Couldn’t load the checklist on this device.'
          : 'Couldn’t load the checklist. Try again.');
    }
    final active = items.valueOrNull;
    if (active == null || !completions.hasValue) {
      return Text(
          offline ? 'Checking saved checklist items…' : 'Loading checklist…');
    }
    if (active.isEmpty) {
      return Text(offline
          ? 'No checklist items saved on this device.'
          : 'No checklist items.');
    }
    final completed = active.where((item) => done.contains(item.id)).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeading(title: widget.delivery.schoolName),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: AppStatusPill(
            label:
                '$completed of ${active.length} checked${offline ? ' on this device' : ''}',
            icon: Icons.checklist_outlined,
            tone: completed == active.length ? AppTone.green : AppTone.blue,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: completed / active.length),
        const SizedBox(height: 12),
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
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ),
      ],
    );
  }
}
