import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/schools_providers.dart';
import '../../models/school.dart';
import '../../models/delivery_visit.dart';
import '../../providers/delivery_visit_provider.dart';
import '../../services/offline/field_draft_store.dart';
import '../../widgets/field_draft_dialog.dart';
import '../../utils/notification_utils.dart';
import '../../utils/year_level_colors.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';

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

    final isVisit = ref.watch(activeDeliveryVisitProvider) != null;
    final yearLevelLabel = yearLevelsAsync.valueOrNull
        ?.where((level) => level.id == yearLevelId)
        .firstOrNull
        ?.label;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(24) * 2 + 12,
        title: Text(
          yearLevelLabel == null
              ? 'Classrooms'
              : '$yearLevelLabel – Classrooms',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
        error: (_, __) => Center(
          child: DeliveryMessage(
            icon: Icons.error_outline,
            title: 'Couldn’t load classrooms',
            action: TextButton(
              onPressed: () => ref.invalidate(classroomsProvider((
                schoolId: schoolId,
                yearLevelId: yearLevelId,
              ))),
              child: const Text('Retry'),
            ),
          ),
        ),
        data: (classrooms) {
          if (classrooms.isEmpty) {
            return Center(
              child: DeliveryMessage(
                icon: Icons.class_outlined,
                title: 'No classrooms found',
                action: FilledButton.icon(
                  onPressed: () => _showAddClassroomDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Classroom'),
                ),
              ),
            );
          }

          final completed = classrooms
              .where((room) =>
                  room.completionStatus == ClassroomCompletionStatus.complete)
              .length;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppTokens.gutter,
              12,
              AppTokens.gutter,
              MediaQuery.paddingOf(context).bottom + 16,
            ),
            children: [
              if (isVisit) ...[
                AppPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pack delivery'),
                      const SizedBox(height: 4),
                      Text(
                        '$completed of ${classrooms.length} classrooms complete',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: completed / classrooms.length,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(99),
                        color: AppTone.green.accent,
                        backgroundColor: AppTone.green.tint,
                        semanticsLabel: 'Pack delivery completion',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              consumablesTotalsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (totals) {
                  if (totals.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return AppPanel(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const AppIconTile(icon: Icons.inventory_2_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Year Level Totals',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final entry in totals.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Text(entry.key)),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    '${entry.value.quantity} ${entry.value.unit}',
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const AppSectionHeading(title: 'Classrooms'),
              const SizedBox(height: 8),
              ...classrooms.map((classroom) {
                return _ClassroomCard(
                  schoolId: schoolId,
                  yearLevelId: yearLevelId,
                  yearLevelLabel: yearLevelLabel ?? '',
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

    final isVisit = ref.watch(activeDeliveryVisitProvider) != null;
    final (statusLabel, statusIcon, statusTone) =
        switch (classroom.completionStatus) {
      ClassroomCompletionStatus.notAttended => (
          'Not Attended',
          Icons.remove_circle_outline,
          AppTone.neutral
        ),
      ClassroomCompletionStatus.incomplete => (
          'Incomplete',
          Icons.warning_amber_rounded,
          AppTone.yellow
        ),
      ClassroomCompletionStatus.complete => (
          'Complete',
          Icons.check_circle_outline,
          AppTone.green
        ),
    };
    final breakdowns = yearLevelBreakdownsAsync.asData?.value;
    final typography = Theme.of(context).textTheme;

    return AppPanel(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(schoolWorkPath(
        schoolId,
        visit: ref.read(activeDeliveryVisitProvider),
        suffix:
            '/year/${Uri.encodeComponent(yearLevelId)}/classrooms/${Uri.encodeComponent(classroom.id)}',
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      needsBorder ? Border.all(color: AppTokens.outline) : null,
                ),
                child: Icon(Icons.meeting_room_outlined,
                    size: 21, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(classroom.name, style: typography.titleMedium),
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isVisit)
                AppStatusPill(
                    label: statusLabel, icon: statusIcon, tone: statusTone),
              if (breakdowns != null && breakdowns.length > 1)
                const AppStatusPill(label: 'Composite', tone: AppTone.blue),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            packTotalAsync.when(
              loading: () => 'Loading pack total…',
              error: (_, __) => 'Pack total unavailable',
              data: (total) => total == null
                  ? 'Pack total: Not set'
                  : 'Pack total: ${total.total}',
            ),
            style: typography.bodyMedium?.copyWith(color: AppTokens.muted),
          ),
          if (breakdowns != null && breakdowns.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${breakdowns.fold<int>(0, (sum, item) => sum + item.studentCount)} students',
              style: typography.bodyMedium?.copyWith(color: AppTone.blue.ink),
            ),
            if (breakdowns.length > 1)
              Text(
                breakdowns
                    .map(
                        (item) => '${item.studentCount} ${item.yearLevelLabel}')
                    .join(', '),
                style: typography.bodySmall?.copyWith(color: AppTokens.muted),
              ),
          ],
        ],
      ),
    );
  }

  void _showEditClassroomDialog(
    BuildContext context,
    WidgetRef ref,
    Classroom classroom,
  ) {
    final schools = ref.read(schoolsNotifierProvider.notifier);
    final visit = ref.read(activeDeliveryVisitProvider);
    showFieldDraftDialog(
      context: context,
      ref: ref,
      target: FieldDraftTarget(
        schoolId: schoolId,
        deliveryId: visit?.deliveryId,
        yearLevelId: yearLevelId,
        classroomId: classroom.id,
        form: 'rename',
      ),
      title: 'Rename classroom',
      savedLabel: 'Classroom name',
      inputs: [
        FieldDraftInput(
          id: 'name',
          label: 'Classroom name',
          initialText: classroom.name,
          validator: (value) {
            final name = value.trim();
            if (name.isEmpty) return 'Enter a classroom name.';
            if (name.length > 200) return 'Use 200 characters or fewer.';
            return null;
          },
        ),
      ],
      onSave: (draft) => schools.updateClassroomName(
        schoolId,
        yearLevelId,
        classroom.id,
        name: draft.values['name']!.trim(),
        editId: draft.revision,
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
