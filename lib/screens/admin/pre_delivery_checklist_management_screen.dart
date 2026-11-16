import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/pre_delivery_checklist_item.dart';
import '../../providers/pre_delivery_checklist_providers.dart';
import '../../providers/auth_providers.dart';
import '../../app/theme/brand_colors.dart';
import '../../widgets/design/design.dart';

class PreDeliveryChecklistManagementScreen extends ConsumerStatefulWidget {
  const PreDeliveryChecklistManagementScreen({super.key});

  @override
  ConsumerState<PreDeliveryChecklistManagementScreen> createState() =>
      _PreDeliveryChecklistManagementScreenState();
}

class _PreDeliveryChecklistManagementScreenState
    extends ConsumerState<PreDeliveryChecklistManagementScreen> {
  @override
  Widget build(BuildContext context) {
    // Initialize default items on first load
    ref.watch(initializePreDeliveryChecklistProvider);

    final checklistAsync = ref.watch(preDeliveryChecklistItemsProvider);
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
        title: const Text('Pre-Delivery Checklist'),
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
                onPressed: () => ref.refresh(preDeliveryChecklistItemsProvider),
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
                      icon: Icons.checklist_rtl,
                      tone: AppTone.neutral,
                      size: 52),
                  const SizedBox(height: 16),
                  const Text(
                    'No checklist items',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add items for staff to check before deliveries',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
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
            padding: const EdgeInsets.fromLTRB(
                AppTokens.gutter, 10, AppTokens.gutter, AppTokens.sectionGap),
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
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
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
                  hintText: 'e.g., Tissues loaded',
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
                  hintText: 'e.g., Check all tissue boxes for delivery',
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
                final item = PreDeliveryChecklistItem(
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
                    .read(preDeliveryChecklistNotifierProvider.notifier)
                    .createChecklistItem(item);

                if (mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Item added successfully'),
                      backgroundColor: Colors.green,
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

  void _showEditItemDialog(PreDeliveryChecklistItem item) {
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
                    .read(preDeliveryChecklistNotifierProvider.notifier)
                    .updateChecklistItem(updatedItem);

                if (mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Item updated successfully'),
                      backgroundColor: Colors.green,
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

  void _toggleItemStatus(PreDeliveryChecklistItem item) async {
    final updatedItem = item.copyWith(isActive: !item.isActive);

    final success = await ref
        .read(preDeliveryChecklistNotifierProvider.notifier)
        .updateChecklistItem(updatedItem);

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Item ${updatedItem.isActive ? 'enabled' : 'disabled'}'),
          backgroundColor: BrandColors.kakaGreen,
        ),
      );
    }
  }

  void _showDeleteConfirmation(PreDeliveryChecklistItem item) {
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
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              final success = await ref
                  .read(preDeliveryChecklistNotifierProvider.notifier)
                  .deleteChecklistItem(item.id);

              if (mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Item deleted'),
                    backgroundColor: Colors.red,
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

  void _reorderItems(
      List<PreDeliveryChecklistItem> items, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final reorderedItems = List<PreDeliveryChecklistItem>.from(items);
    final movedItem = reorderedItems.removeAt(oldIndex);
    reorderedItems.insert(newIndex, movedItem);

    // Update order values
    for (int i = 0; i < reorderedItems.length; i++) {
      reorderedItems[i] = reorderedItems[i].copyWith(order: i + 1);
    }

    ref
        .read(preDeliveryChecklistNotifierProvider.notifier)
        .reorderChecklistItems(reorderedItems);
  }
}
