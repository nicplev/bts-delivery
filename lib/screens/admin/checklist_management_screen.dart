import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/checklist_item.dart';
import '../../providers/checklist_providers.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';
import 'admin_page.dart';
import 'checklist_admin_list.dart';

class ChecklistManagementScreen extends ConsumerStatefulWidget {
  const ChecklistManagementScreen({super.key});

  @override
  ConsumerState<ChecklistManagementScreen> createState() =>
      _ChecklistManagementScreenState();
}

class _ChecklistManagementScreenState
    extends ConsumerState<ChecklistManagementScreen> {
  @override
  Widget build(BuildContext context) {
    // Initialize default items on first load
    ref.watch(initializeChecklistProvider);

    final checklistAsync = ref.watch(checklistItemsProvider);
    final isAdmin = ref.watch(isAdminProvider);

    if (!isAdmin) {
      return const AdminPage(
        backLabel: 'Back to profile',
        title: 'Access denied',
        children: [
          DeliveryMessage(
            icon: AppIcons.lock,
            title: 'Admin access required',
          ),
        ],
      );
    }

    const title = 'Pre-sign-off checklist';
    final action = AppGlassPrimaryButton(
      label: 'Add item',
      icon: AppIcons.add,
      onPressed: _showAddItemDialog,
    );

    return checklistAsync.when(
      loading: () => AdminPage(
        backLabel: 'Back to profile',
        title: title,
        action: action,
        children: const [AdminLoading()],
      ),
      error: (error, _) => AdminPage(
        backLabel: 'Back to profile',
        title: title,
        action: action,
        children: [
          DeliveryMessage(
            icon: AppIcons.error,
            title: 'Error: $error',
            action: AppSecondaryButton(
              label: 'Retry',
              icon: AppIcons.retry,
              onPressed: () => ref.refresh(checklistItemsProvider),
            ),
          ),
        ],
      ),
      data: (items) => AdminPage(
        backLabel: 'Back to profile',
        title: title,
        action: action,
        slivers: [
          if (items.isEmpty)
            const SliverToBoxAdapter(
              child: DeliveryMessage(
                icon: AppIcons.checklist,
                title: 'No checklist items',
                description: 'Use Add item to create the first item.',
              ),
            )
          else
            ChecklistAdminList(
              entries: [
                for (final item in items)
                  (
                    id: item.id,
                    title: item.title,
                    subtitle: item.subtitle,
                    isActive: item.isActive,
                  ),
              ],
              onReorder: (oldIndex, newIndex) =>
                  _reorderItems(items, oldIndex, newIndex),
              onEdit: (index) => _showEditItemDialog(items[index]),
              onToggle: (index) => _toggleItemStatus(items[index]),
              onDelete: (index) => _showDeleteConfirmation(items[index]),
            ),
        ],
      ),
    );
  }

  void _showAddItemDialog() {
    final titleController = TextEditingController();
    final subtitleController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Add checklist item'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g., Extra supplies delivered to office',
                ),
                validator: (value) =>
                    value?.trim().isEmpty ?? true ? 'Title is required' : null,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: subtitleController,
                decoration: const InputDecoration(
                  labelText: 'Subtitle (optional)',
                  hintText: 'e.g., (i.e. L/H Scissors)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop();

                final currentUser = ref.read(currentUserProvider).value;
                final item = ChecklistItem(
                  id: '',
                  title: titleController.text.trim(),
                  subtitle: subtitleController.text.trim().isEmpty
                      ? null
                      : subtitleController.text.trim(),
                  order: 0, // Will be set by repository
                  createdAt: DateTime.now(),
                  createdBy: currentUser?.email,
                );

                final success = await ref
                    .read(checklistNotifierProvider.notifier)
                    .createChecklistItem(item);

                if (mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Item added successfully'),
                    ),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditItemDialog(ChecklistItem item) {
    final titleController = TextEditingController(text: item.title);
    final subtitleController = TextEditingController(text: item.subtitle ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Edit checklist item'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                ),
                validator: (value) =>
                    value?.trim().isEmpty ?? true ? 'Title is required' : null,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: subtitleController,
                decoration: const InputDecoration(
                  labelText: 'Subtitle (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop();

                final updatedItem = item.copyWith(
                  title: titleController.text.trim(),
                  subtitle: subtitleController.text.trim().isEmpty
                      ? null
                      : subtitleController.text.trim(),
                );

                final success = await ref
                    .read(checklistNotifierProvider.notifier)
                    .updateChecklistItem(updatedItem);

                if (mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Item updated successfully'),
                    ),
                  );
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _toggleItemStatus(ChecklistItem item) async {
    final updatedItem = item.copyWith(isActive: !item.isActive);

    final success = await ref
        .read(checklistNotifierProvider.notifier)
        .updateChecklistItem(updatedItem);

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Item ${updatedItem.isActive ? 'enabled' : 'disabled'}'),
        ),
      );
    }
  }

  void _showDeleteConfirmation(ChecklistItem item) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Delete item'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: appDestructiveButtonStyle(context),
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              final success = await ref
                  .read(checklistNotifierProvider.notifier)
                  .deleteChecklistItem(item.id);

              if (mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Item deleted'),
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _reorderItems(List<ChecklistItem> items, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final reorderedItems = List<ChecklistItem>.from(items);
    final movedItem = reorderedItems.removeAt(oldIndex);
    reorderedItems.insert(newIndex, movedItem);

    // Update order values
    for (int i = 0; i < reorderedItems.length; i++) {
      reorderedItems[i] = reorderedItems[i].copyWith(order: i + 1);
    }

    ref
        .read(checklistNotifierProvider.notifier)
        .reorderChecklistItems(reorderedItems);
  }
}
