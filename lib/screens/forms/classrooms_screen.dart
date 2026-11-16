import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/schools_providers.dart';
import '../../models/school.dart';
import '../../models/delivery_visit.dart';
import '../../providers/delivery_visit_provider.dart';
import '../../repositories/classroom_edit.dart';
import '../../utils/notification_utils.dart';
import '../../utils/year_level_colors.dart';

class ClassroomsScreen extends ConsumerWidget {
  const ClassroomsScreen({
    super.key,
    required this.schoolId,
    required this.yearLevelId,
  });

  final String schoolId;
  final String yearLevelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classroomsAsync = ref.watch(classroomsProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
    )));
    final yearLevelsAsync = ref.watch(yearLevelsProvider(schoolId));
    final consumablesTotalsAsync =
        ref.watch(yearLevelConsumablesTotalsProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
    )));

    return Scaffold(
      appBar: AppBar(
        title: yearLevelsAsync.when(
          data: (yearLevels) {
            final yearLevel = yearLevels.firstWhere(
              (yl) => yl.id == yearLevelId,
              orElse: () => YearLevel(
                id: '',
                label: 'Classrooms',
                createdAt: DateTime.now(),
              ),
            );
            return Text('${yearLevel.label} - Classrooms');
          },
          loading: () => const Text('Classrooms'),
          error: (_, __) => const Text('Classrooms'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddClassroomDialog(context, ref),
            tooltip: 'Add Classroom',
          ),
        ],
      ),
      body: classroomsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(classroomsProvider((
                  schoolId: schoolId,
                  yearLevelId: yearLevelId,
                ))),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (classrooms) {
          // Get year level label for color coding
          final yearLevel = yearLevelsAsync.value?.firstWhere(
            (yl) => yl.id == yearLevelId,
            orElse: () => YearLevel(
              id: '',
              label: '',
              createdAt: DateTime.now(),
            ),
          );
          final yearLevelLabel = yearLevel?.label ?? '';

          if (classrooms.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.class_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No classrooms found',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add classrooms to start tracking supplies',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _showAddClassroomDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Classroom'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Year Level Consumables Totals Card
              consumablesTotalsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (totals) {
                  if (totals.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2,
                                color: YearLevelColors.getBackgroundColor(yearLevelLabel),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Year Level Totals',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...totals.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(entry.key),
                                  Text(
                                    '${entry.value.quantity} ${entry.value.unit}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Classrooms List
              ...classrooms.map((classroom) {
                return _ClassroomCard(
                  schoolId: schoolId,
                  yearLevelId: yearLevelId,
                  yearLevelLabel: yearLevelLabel,
                  classroom: classroom,
                );
              }),
            ],
          );
        },
      ),
    );
  }

  void _showAddClassroomDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Classroom'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Classroom Name',
              hintText: 'e.g., Room 1A, Blue Room',
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

              final classroom = Classroom(
                id: '',
                name: nameController.text.trim(),
                createdAt: DateTime.now(),
              );

              final success = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .createClassroom(schoolId, yearLevelId, classroom);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Classroom created successfully'
                        : 'Failed to create classroom'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );

                // Show notification that sign-off was cleared
                if (success) {
                  NotificationUtils.showSignOffClearedNotification(context);
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _ClassroomCard extends ConsumerWidget {
  const _ClassroomCard({
    required this.schoolId,
    required this.yearLevelId,
    required this.yearLevelLabel,
    required this.classroom,
  });

  final String schoolId;
  final String yearLevelId;
  final String yearLevelLabel;
  final Classroom classroom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packTotalAsync = ref.watch(packTotalProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));
    final yearLevelBreakdownsAsync = ref.watch(yearLevelBreakdownsProvider((
      schoolId: schoolId,
      yearLevelId: yearLevelId,
      classroomId: classroom.id,
    )));

    final backgroundColor = YearLevelColors.getBackgroundColor(yearLevelLabel);
    final iconColor = YearLevelColors.getIconColor(yearLevelLabel);
    final needsBorder = YearLevelColors.needsBorder(yearLevelLabel);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(schoolWorkPath(
          schoolId,
          visit: ref.read(activeDeliveryVisitProvider),
          suffix: '/year/${Uri.encodeComponent(yearLevelId)}/classrooms/${Uri.encodeComponent(classroom.id)}',
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
                  child: Icon(Icons.meeting_room, color: iconColor),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          classroom.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        yearLevelBreakdownsAsync.maybeWhen(
                          data: (breakdowns) {
                            if (breakdowns.length > 1) {
                              return Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.orange.shade700,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'Composite',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    packTotalAsync.when(
                      loading: () => const Text(
                        'Loading pack total...',
                        style: TextStyle(color: Colors.grey),
                      ),
                      error: (_, __) => const Text(
                        'Pack total: --',
                        style: TextStyle(color: Colors.grey),
                      ),
                      data: (packTotal) => Text(
                        packTotal != null
                            ? 'Pack total: ${packTotal.total}'
                            : 'Pack total: Not set',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                    yearLevelBreakdownsAsync.maybeWhen(
                      data: (breakdowns) {
                        if (breakdowns.isNotEmpty) {
                          final totalStudents = breakdowns.fold<int>(
                            0,
                            (sum, b) => sum + b.studentCount,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.people,
                                  size: 14,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$totalStudents ${totalStudents == 1 ? "student" : "students"}',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (breakdowns.length > 1) ...[
                                  const Text(
                                    ' (',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    breakdowns
                                        .map((b) => '${b.studentCount} ${b.yearLevelLabel}')
                                        .join(', '),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const Text(
                                    ')',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                offset: const Offset(0, 8),
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditClassroomDialog(context, ref, classroom);
                  } else if (value == 'delete') {
                    _showDeleteConfirmation(context, ref, classroom);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  void _showEditClassroomDialog(
    BuildContext context,
    WidgetRef ref,
    Classroom classroom,
  ) {
    final nameController = TextEditingController(text: classroom.name);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Classroom'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Classroom Name',
              hintText: 'e.g., Room 1A, Blue Room',
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

              final name = nameController.text.trim();
              Navigator.pop(dialogContext);

              final result = await ref
                  .read(schoolsNotifierProvider.notifier)
                  .updateClassroomName(schoolId, yearLevelId, classroom.id, name: name);
              if (!context.mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.when(
                    success: (progress) => switch (progress) {
                      ClassroomEditStatus.saved => 'Classroom name saved',
                      ClassroomEditStatus.pending => 'Classroom name saved on this device · Sync pending',
                      ClassroomEditStatus.unconfirmed => 'Waiting to confirm the classroom name change',
                    },
                    failure: (message, _) => message,
                  )),
                ),
              );
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
    Classroom classroom,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Classroom'),
        content: Text(
          'Are you sure you want to delete "${classroom.name}"? This action cannot be undone.',
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
                  .deleteClassroom(schoolId, yearLevelId, classroom.id);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Classroom deleted successfully'
                        : 'Failed to delete classroom'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );

                // Show notification that sign-off was cleared
                if (success) {
                  NotificationUtils.showSignOffClearedNotification(context);
                }
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
