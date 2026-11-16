import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/schools_providers.dart';
import '../providers/auth_providers.dart';
import '../models/school.dart';
import '../models/delivery_visit.dart';
import '../providers/delivery_visit_provider.dart';
import '../utils/year_level_colors.dart';

class RecordsTab extends ConsumerWidget {
  const RecordsTab({super.key, required this.schoolId});

  final String schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yearLevelsAsync = ref.watch(yearLevelsProvider(schoolId));

    return Column(
      children: [
        // Year Levels section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Year Levels',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    if (ref.watch(canEditSchoolDataProvider))
                      TextButton.icon(
                        onPressed: () => _showAddYearLevelDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Year Level'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: yearLevelsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: $error'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              ref.invalidate(yearLevelsProvider(schoolId)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                  data: (yearLevels) {
                    if (yearLevels.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.class_outlined,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No year levels found'),
                            SizedBox(height: 8),
                            Text(
                              'Add year levels to organize classrooms',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: yearLevels.length,
                      itemBuilder: (context, index) {
                        final yearLevel = yearLevels[index];
                        return _YearLevelCard(
                          schoolId: schoolId,
                          yearLevel: yearLevel,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddYearLevelDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Year Level'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Year Level Name',
            hintText: 'e.g., Prep, Year 1, Grade 2',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;

              final yearLevel = YearLevel(
                id: '',
                label: controller.text.trim(),
                createdAt: DateTime.now(),
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .createYearLevel(schoolId, yearLevel);

              if (success && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _YearLevelCard extends ConsumerWidget {
  const _YearLevelCard({
    required this.schoolId,
    required this.yearLevel,
  });

  final String schoolId;
  final YearLevel yearLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classroomsAsync = ref.watch(
        classroomsProvider((schoolId: schoolId, yearLevelId: yearLevel.id)));
    final backgroundColor = YearLevelColors.getBackgroundColor(yearLevel.label);
    final iconColor = YearLevelColors.getIconColor(yearLevel.label);
    final needsBorder = YearLevelColors.needsBorder(yearLevel.label);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(schoolWorkPath(
          schoolId,
          visit: ref.read(activeDeliveryVisitProvider),
          suffix: '/year/${Uri.encodeComponent(yearLevel.id)}/classrooms',
        )),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                decoration: needsBorder
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      )
                    : null,
                child: CircleAvatar(
                  backgroundColor: backgroundColor,
                  child: Icon(Icons.class_, color: iconColor),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      yearLevel.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    classroomsAsync.when(
                      loading: () => const Text('Loading classrooms...',
                          style: TextStyle(color: Colors.grey)),
                      error: (_, __) => const Text('Error loading classrooms',
                          style: TextStyle(color: Colors.red)),
                      data: (classrooms) => Text(
                        '${classrooms.length} classroom${classrooms.length != 1 ? 's' : ''}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              if (ref.watch(canEditSchoolDataProvider))
                PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                  offset: const Offset(0, 8),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showEditYearLevelDialog(context, ref, yearLevel);
                    } else if (value == 'delete') {
                      _showDeleteConfirmation(context, ref, yearLevel);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditYearLevelDialog(
    BuildContext context,
    WidgetRef ref,
    YearLevel yearLevel,
  ) {
    final nameController = TextEditingController(text: yearLevel.label);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Year Level'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Year Level Name',
              hintText: 'e.g., Prep, Year 1, Grade 2',
            ),
            autofocus: true,
            validator: (value) =>
                value?.trim().isEmpty ?? true ? 'Please enter a name' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              Navigator.pop(dialogContext);

              final updatedYearLevel = YearLevel(
                id: yearLevel.id,
                label: nameController.text.trim(),
                createdAt: yearLevel.createdAt,
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .updateYearLevel(schoolId, updatedYearLevel);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Year level updated successfully'
                        : 'Failed to update year level'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    YearLevel yearLevel,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Year Level'),
        content: Text(
          'Are you sure you want to delete "${yearLevel.label}"? This will also delete all classrooms within this year level. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .deleteYearLevel(schoolId, yearLevel.id);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Year level deleted successfully'
                        : 'Failed to delete year level'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
