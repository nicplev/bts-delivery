import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/checklist_item.dart';
import '../../providers/checklist_providers.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/design/design.dart';

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
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text('Admin access required'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-Signoff Checklist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddItemDialog(),
            tooltip: 'Add Item',
          ),
        ],
      ),
      body: checklistAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $error'),
              ElevatedButton(
                onPressed: () => ref.refresh(checklistItemsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppIconTile(
                      icon: Icons.checklist, tone: AppTone.neutral, size: 52),
                  const SizedBox(height: 16),
                  const Text(
                    'No checklist items',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showAddItemDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Item'),
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: EdgeInsets.fromLTRB(AppTokens.gutter, 10, AppTokens.gutter,
                MediaQuery.paddingOf(context).bottom + AppTokens.sectionGap),
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) =>
                _reorderItems(items, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final item = items[index];
              return AppPanel(
                key: ValueKey(item.id),
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: Semantics(
                      label: 'Reorder item',
                      child: const SizedBox.square(
                        dimension: 44,
                        child: Center(
                          child: AppIconTile(
                            icon: Icons.drag_handle,
                            tone: AppTone.neutral,
                          ),
                        ),
                      ),
                    ),
                  ),
                  title: Text(item.title),
                  subtitle: item.subtitle != null || !item.isActive
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.subtitle != null) Text(item.subtitle!),
                            if (!item.isActive)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: AppStatusPill(
                                  label: 'Disabled',
                                  icon: Icons.pause_circle_outline,
                                ),
                              ),
                          ],
                        )
                      : null,
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Checklist item actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showEditItemDialog(item);
                          break;
                        case 'toggle':
                          _toggleItemStatus(item);
                          break;
                        case 'delete':
                          _showDeleteConfirmation(item);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 12),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Row(
                          children: [
                            Icon(
                              item.isActive
                                  ? Icons.toggle_off
                                  : Icons.toggle_on,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(item.isActive ? 'Disable' : 'Enable'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete,
                                size: 20,
                                color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 12),
                            Text('Delete',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
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
        title: const Text('Add Checklist Item'),
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
        title: const Text('Edit Checklist Item'),
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
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
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
