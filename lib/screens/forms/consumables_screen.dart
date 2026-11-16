import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/schools_providers.dart';
import '../../models/school.dart';
import '../../widgets/design/design.dart';
import '../../widgets/delivery_day_list.dart';
import '../../utils/notification_utils.dart';

class ConsumablesScreen extends ConsumerWidget {
  const ConsumablesScreen({super.key, required this.schoolId});

  final String schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consumablesAsync = ref.watch(consumablesProvider(schoolId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consumables'),
      ),
      body: consumablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: DeliveryMessage(
            icon: Icons.error_outline,
            title: 'Couldn’t load consumables',
            action: TextButton(
              onPressed: () => ref.invalidate(consumablesProvider(schoolId)),
              child: const Text('Retry'),
            ),
          ),
        ),
        data: (consumables) {
          if (consumables.isEmpty) {
            return const Center(
              child: DeliveryMessage(
                icon: Icons.inventory_2_outlined,
                title: 'No consumables recorded',
                description: 'Tap + to add school-wide supplies and materials.',
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              AppTokens.gutter,
              12,
              AppTokens.gutter,
              MediaQuery.paddingOf(context).bottom + 80,
            ),
            itemCount: consumables.length,
            itemBuilder: (context, index) {
              final consumable = consumables[index];
              return AppPanel(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const AppIconTile(icon: Icons.inventory_2_outlined),
                  title: Text(consumable.itemName),
                  subtitle: Text('${consumable.quantity} ${consumable.unit}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showEditConsumableDialog(context, ref, consumable);
                          break;
                        case 'delete':
                          _showDeleteDialog(context, ref, consumable);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete, color: Colors.red),
                          title: Text('Delete',
                              style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddConsumableDialog(context, ref),
        tooltip: 'Add Consumable',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddConsumableDialog(BuildContext context, WidgetRef ref) {
    _showConsumableDialog(context, ref, null);
  }

  void _showEditConsumableDialog(
      BuildContext context, WidgetRef ref, Consumable consumable) {
    _showConsumableDialog(context, ref, consumable);
  }

  void _showConsumableDialog(
      BuildContext context, WidgetRef ref, Consumable? consumable) {
    final isEditing = consumable != null;
    final nameController =
        TextEditingController(text: consumable?.itemName ?? '');
    final quantityController =
        TextEditingController(text: consumable?.quantity.toString() ?? '');
    final unitController = TextEditingController(text: consumable?.unit ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Consumable' : 'Add Consumable'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  hintText: 'e.g., Copy Paper A4',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter item name';
                  }
                  return null;
                },
                autofocus: !isEditing,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  hintText: 'e.g., 6',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter quantity';
                  }
                  if (int.tryParse(value.trim()) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  hintText: 'e.g., reams, boxes, packs',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter unit';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final newConsumable = Consumable(
                id: consumable?.id ?? '',
                itemName: nameController.text.trim(),
                quantity: int.parse(quantityController.text.trim()),
                unit: unitController.text.trim(),
                createdAt: consumable?.createdAt ?? DateTime.now(),
              );

              // Show loading state
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );

              final success = isEditing
                  ? await ref
                      .read(schoolsNotifierProvider.notifier)
                      .updateConsumable(schoolId, newConsumable)
                  : await ref
                      .read(schoolsNotifierProvider.notifier)
                      .createConsumable(schoolId, newConsumable);

              if (context.mounted) {
                Navigator.pop(context); // Close loading dialog

                if (success) {
                  Navigator.pop(context); // Close edit dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEditing
                          ? 'Consumable updated successfully'
                          : 'Consumable added successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );

                  // Show notification that sign-off was cleared
                  NotificationUtils.showSignOffClearedNotification(context);
                } else {
                  // Show error message
                  final errorState = ref.read(schoolsNotifierProvider);
                  final errorMessage = errorState is AsyncError
                      ? errorState.error.toString()
                      : 'Failed to save consumable';

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
      BuildContext context, WidgetRef ref, Consumable consumable) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Consumable'),
        content:
            Text('Are you sure you want to delete "${consumable.itemName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .deleteConsumable(schoolId, consumable.id);

              if (success && context.mounted) {
                Navigator.pop(context);
                // Show notification that sign-off was cleared
                NotificationUtils.showSignOffClearedNotification(context);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
