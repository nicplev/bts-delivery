import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pre_delivery_checklist_item.dart';
import '../models/delivery.dart';
import '../providers/pre_delivery_checklist_providers.dart';
import '../providers/auth_providers.dart';
import '../app/theme/brand_colors.dart';

/// Shows a pre-delivery checklist dialog for a specific delivery.
/// Returns true if the dialog was closed with all items complete, false otherwise.
Future<bool> showPreDeliveryChecklistDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Delivery delivery,
}) async {
  // Initialize default checklist items on first use
  await ref.read(initializePreDeliveryChecklistProvider.future);

  // Get active checklist items
  final activeItems = await ref.read(activePreDeliveryChecklistItemsProvider.future);

  // If no checklist items, return true (nothing to check)
  if (activeItems.isEmpty) {
    return true;
  }

  // Get current completions for this delivery
  final completions = await ref.read(deliveryCompletionsProvider(delivery.id).future);

  // Build a map of itemId -> isCompleted
  final Map<String, bool> completionMap = {};
  for (final item in activeItems) {
    final completion = completions.where((c) => c.itemId == item.id).firstOrNull;
    completionMap[item.id] = completion?.isCompleted ?? false;
  }

  if (!context.mounted) return false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _PreDeliveryChecklistDialogContent(
      delivery: delivery,
      activeItems: activeItems,
      initialCompletionMap: completionMap,
    ),
  );

  return result ?? false;
}

class _PreDeliveryChecklistDialogContent extends ConsumerStatefulWidget {
  const _PreDeliveryChecklistDialogContent({
    required this.delivery,
    required this.activeItems,
    required this.initialCompletionMap,
  });

  final Delivery delivery;
  final List<PreDeliveryChecklistItem> activeItems;
  final Map<String, bool> initialCompletionMap;

  @override
  ConsumerState<_PreDeliveryChecklistDialogContent> createState() =>
      _PreDeliveryChecklistDialogContentState();
}

class _PreDeliveryChecklistDialogContentState
    extends ConsumerState<_PreDeliveryChecklistDialogContent> {
  late Map<String, bool> _checkedItems;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _checkedItems = Map.from(widget.initialCompletionMap);
  }

  int get _checkedCount => _checkedItems.values.where((v) => v).length;
  int get _totalItems => _checkedItems.length;
  bool get _allChecked => _checkedItems.values.every((v) => v);

  Future<void> _toggleItem(String itemId, bool value) async {
    setState(() {
      _checkedItems[itemId] = value;
      _isSaving = true;
    });

    // Get current user email
    final currentUser = ref.read(currentUserProvider).value;
    final userEmail = currentUser?.email;

    // Persist to Firestore
    await ref
        .read(preDeliveryChecklistNotifierProvider.notifier)
        .updateCompletion(widget.delivery.id, itemId, value, userEmail);

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _allChecked ? Icons.check_circle : Icons.checklist_rtl,
            color: _allChecked ? Colors.green : BrandColors.kakaBlue,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Pre-Delivery Checklist'),
          ),
          if (_isSaving)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verify items for: ${widget.delivery.schoolName}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            // Checklist items
            ...widget.activeItems.map((item) {
              return CheckboxListTile(
                value: _checkedItems[item.id] ?? false,
                onChanged: (value) => _toggleItem(item.id, value ?? false),
                title: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 14,
                    decoration: (_checkedItems[item.id] ?? false)
                        ? TextDecoration.lineThrough
                        : null,
                    color: (_checkedItems[item.id] ?? false)
                        ? Colors.grey
                        : null,
                  ),
                ),
                subtitle: item.subtitle != null
                    ? Text(
                        item.subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      )
                    : null,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.green,
              );
            }),
            const SizedBox(height: 16),
            // Progress indicator
            LinearProgressIndicator(
              value: _totalItems > 0 ? _checkedCount / _totalItems : 0,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                _allChecked ? Colors.green : BrandColors.kakaBlue,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_allChecked) ...[
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  const Text(
                    'All items completed!',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else
                  Text(
                    '$_checkedCount of $_totalItems items completed',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_allChecked),
          child: Text(_allChecked ? 'Done' : 'Close'),
        ),
      ],
    );
  }
}
