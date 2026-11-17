import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/schools_providers.dart';
import '../../models/school.dart';
import '../../widgets/design/design.dart';
import '../../widgets/delivery_day_list.dart';
import '../../utils/notification_utils.dart';

/// School-wide consumables: large title, grouped rows with edit/delete, and
/// one floating "Add consumable" action.
class ConsumablesScreen extends ConsumerWidget {
  const ConsumablesScreen({super.key, required this.schoolId});

  final String schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consumablesAsync = ref.watch(consumablesProvider(schoolId));
    final count = consumablesAsync.valueOrNull?.length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppNavBar(backLabel: 'Back to school'),
      body: AppFloatingActionArea(
        action: AppGlassPrimaryButton(
          key: const ValueKey('add-consumable'),
          label: 'Add consumable',
          icon: AppIcons.add,
          onPressed: () => _showConsumableDialog(context, ref, null),
        ),
        child: Builder(
          builder: (context) => ListView(
            padding: AppInsets.scroll(context),
            children: [
              AppLargeTitle(
                title: 'Consumables',
                subtitle: count == null || count == 0
                    ? 'School-wide supplies and materials'
                    : count == 1
                        ? '1 item'
                        : '$count items',
              ),
              const SizedBox(height: 20),
              consumablesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => DeliveryMessage(
                  icon: AppIcons.error,
                  title: 'Couldn’t load consumables',
                  action: AppSecondaryButton(
                    label: 'Retry',
                    icon: AppIcons.retry,
                    expand: false,
                    onPressed: () =>
                        ref.invalidate(consumablesProvider(schoolId)),
                  ),
                ),
                data: (consumables) {
                  if (consumables.isEmpty) {
                    return const DeliveryMessage(
                      icon: AppIcons.consumables,
                      title: 'No consumables recorded',
                      description:
                          'Use Add consumable to add school-wide supplies and materials.',
                    );
                  }
                  return AppGroupedList(
                    separatorIndent: 57,
                    children: [
                      for (final consumable in consumables)
                        AppListRow(
                          key: ValueKey(consumable.id),
                          icon: AppIcons.consumables,
                          title: consumable.itemName,
                          subtitle: '${consumable.quantity} ${consumable.unit}',
                          onTap: () =>
                              _showConsumableDialog(context, ref, consumable),
                          showChevron: false,
                          trailing: AppMenuButton<String>(
                            tooltip: '${consumable.itemName} options',
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _showConsumableDialog(
                                      context, ref, consumable);
                                  break;
                                case 'delete':
                                  _showDeleteDialog(context, ref, consumable);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              appMenuItem(context, 'edit', 'Edit',
                                  icon: AppIcons.edit),
                              appMenuItem(context, 'delete', 'Delete',
                                  icon: AppIcons.delete, destructive: true),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
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
        scrollable: true,
        title: Text(isEditing ? 'Edit consumable' : 'Add consumable'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Item name',
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete consumable?'),
          content:
              Text('Are you sure you want to delete "${consumable.itemName}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: appDestructiveButtonStyle(context),
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
        );
      },
    );
  }
}
