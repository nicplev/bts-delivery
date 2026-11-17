import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_providers.dart';
import '../../providers/schools_providers.dart';
import '../../models/school.dart';
import '../../models/delivery_visit.dart';
import '../../providers/delivery_visit_provider.dart';
import '../../services/offline/field_draft_store.dart';
import '../../widgets/classroom_record_row.dart';
import '../../widgets/field_draft_dialog.dart';
import '../../utils/notification_utils.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';
import 'year_levels_screen.dart';

/// One year level's classrooms: the year badge and name as the header, the
/// visit progress, year totals and the classroom rows. "Add classroom" is the
/// floating primary action; rename / delete live in each row's options and
/// the year level's own options in the nav bar.
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
    final canEditYearLevel = ref.watch(canEditSchoolDataProvider);
    final yearLevel = yearLevelsAsync.valueOrNull
        ?.where((level) => level.id == yearLevelId)
        .firstOrNull;
    final yearLevelLabel = yearLevel?.label;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppNavBar(
        backLabel: isVisit ? 'Back to visit' : 'Back to school',
        actions: [
          if (canEditYearLevel && yearLevel != null)
            AppGlassIconButton(
              key: const ValueKey('year-level-options'),
              icon: AppIcons.more,
              semanticLabel: 'Year level options',
              onPressed: () => _showYearLevelOptions(context, ref, yearLevel),
            ),
        ],
      ),
      body: AppFloatingActionArea(
        action: AppGlassPrimaryButton(
          key: const ValueKey('add-classroom'),
          label: 'Add classroom',
          icon: AppIcons.add,
          onPressed: () => _showAddClassroomDialog(context, ref),
        ),
        child: Builder(builder: (context) {
          final header = <Widget>[
            if (yearLevelLabel != null) ...[
              AppYearBadge(label: yearLevelLabel, size: 44),
              const SizedBox(height: 12),
            ],
            AppLargeTitle(
              title: yearLevelLabel ?? 'Classrooms',
              subtitle: classroomsAsync.whenOrNull(
                data: (rooms) => rooms.isEmpty
                    ? 'Classrooms'
                    : '${rooms.length} classroom${rooms.length == 1 ? '' : 's'}',
              ),
            ),
            const SizedBox(height: 16),
          ];
          final body = classroomsAsync.when<List<Widget>>(
            loading: () => const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (_, __) => [
              AppPanel(
                child: DeliveryMessage(
                  icon: AppIcons.error,
                  title: 'Couldn’t load classrooms',
                  action: AppSecondaryButton(
                    label: 'Retry',
                    icon: AppIcons.retry,
                    expand: false,
                    large: false,
                    onPressed: () => ref.invalidate(classroomsProvider((
                      schoolId: schoolId,
                      yearLevelId: yearLevelId,
                    ))),
                  ),
                ),
              ),
            ],
            data: (classrooms) {
              if (classrooms.isEmpty) {
                return const [
                  AppPanel(
                    child: DeliveryMessage(
                      icon: AppIcons.classroom,
                      title: 'No classrooms found',
                      description: 'Use “Add classroom” to create one.',
                    ),
                  ),
                ];
              }
              final completed = classrooms
                  .where((room) =>
                      room.completionStatus ==
                      ClassroomCompletionStatus.complete)
                  .length;
              final colors = AppPalette.of(context);
              return [
                if (isVisit) ...[
                  AppPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Pack delivery',
                            style: AppTypography.footnote.copyWith(
                                color: colors.muted,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          '$completed of ${classrooms.length} classrooms complete',
                          style:
                              AppTypography.title3.copyWith(color: colors.ink),
                        ),
                        const SizedBox(height: 12),
                        AppProgressBar(
                          value: completed / classrooms.length,
                          semanticLabel: 'Pack delivery completion',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.sectionGap),
                ],
                ...consumablesTotalsAsync.maybeWhen(
                  orElse: () => const <Widget>[],
                  data: (totals) => totals.isEmpty
                      ? const <Widget>[]
                      : [
                          const AppSectionLabel('Year level totals'),
                          const SizedBox(height: 8),
                          AppGroupedList(
                            separatorIndent: 57,
                            children: [
                              for (final entry in totals.entries)
                                AppListRow(
                                  icon: AppIcons.consumables,
                                  title: entry.key,
                                  detail:
                                      '${entry.value.quantity} ${entry.value.unit}',
                                ),
                            ],
                          ),
                          const SizedBox(height: AppTokens.sectionGap),
                        ],
                ),
                const AppSectionLabel('Classrooms'),
                const SizedBox(height: 8),
                AppGroupedList(
                  separatorIndent: 64,
                  children: [
                    for (final classroom in classrooms)
                      _ClassroomRow(
                        key: ValueKey('classroom-${classroom.id}'),
                        schoolId: schoolId,
                        yearLevelId: yearLevelId,
                        yearLevelLabel: yearLevelLabel ?? '',
                        classroom: classroom,
                        isVisit: isVisit,
                      ),
                  ],
                ),
              ];
            },
          );
          return ListView(
            padding: AppInsets.scroll(context),
            children: [...header, ...body],
          );
        }),
      ),
    );
  }

  void _showYearLevelOptions(
    BuildContext context,
    WidgetRef ref,
    YearLevel yearLevel,
  ) {
    showAppGlassSheet<void>(
      context: context,
      title: yearLevel.label,
      builder: (sheetContext) {
        void run(void Function() action) {
          Navigator.of(sheetContext).pop();
          if (context.mounted) action();
        }

        final colors = AppPalette.of(sheetContext);
        return SingleChildScrollView(
          child: AppGroupedList(
            separatorIndent: 57,
            children: [
              AppListRow(
                key: const ValueKey('rename-year-level'),
                icon: AppIcons.edit,
                title: 'Rename year level',
                onTap: () => run(() =>
                    showEditYearLevelDialog(context, ref, schoolId, yearLevel)),
              ),
              AppListRow(
                key: const ValueKey('delete-year-level'),
                icon: AppIcons.delete,
                title: 'Delete year level',
                titleStyle: AppTypography.body.copyWith(color: colors.error),
                onTap: () => run(() => showDeleteYearLevelDialog(
                      context,
                      ref,
                      schoolId,
                      yearLevel,
                      onDeleted: () {
                        if (context.mounted) appNavigateBack(context);
                      },
                    )),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddClassroomDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add classroom'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Classroom name',
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

class _ClassroomRow extends ConsumerWidget {
  const _ClassroomRow({
    super.key,
    required this.schoolId,
    required this.yearLevelId,
    required this.yearLevelLabel,
    required this.classroom,
    required this.isVisit,
  });

  final String schoolId;
  final String yearLevelId;
  final String yearLevelLabel;
  final Classroom classroom;
  final bool isVisit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdowns = ref
        .watch(yearLevelBreakdownsProvider((
          schoolId: schoolId,
          yearLevelId: yearLevelId,
          classroomId: classroom.id,
        )))
        .asData
        ?.value;
    final colors = AppPalette.of(context);
    final students = breakdowns == null || breakdowns.isEmpty
        ? null
        : breakdowns.fold<int>(0, (sum, item) => sum + item.studentCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClassroomRecordRow(
          schoolId: schoolId,
          yearLevelId: yearLevelId,
          yearLevelLabel: yearLevelLabel,
          classroom: classroom,
          isVisit: isVisit,
          onTap: () => context.push(schoolWorkPath(
            schoolId,
            visit: ref.read(activeDeliveryVisitProvider),
            suffix:
                '/year/${Uri.encodeComponent(yearLevelId)}/classrooms/${Uri.encodeComponent(classroom.id)}',
          )),
          action: AppMenuButton<String>(
            tooltip: 'Classroom options',
            onSelected: (value) {
              if (value == 'edit') {
                _showEditClassroomDialog(context, ref, classroom);
              } else if (value == 'delete') {
                _showDeleteConfirmation(context, ref, classroom);
              }
            },
            itemBuilder: (context) => [
              appMenuItem(context, 'edit', 'Rename', icon: AppIcons.edit),
              appMenuItem(context, 'delete', 'Delete',
                  icon: AppIcons.delete, destructive: true),
            ],
          ),
        ),
        if (students != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 0, 16, 10),
            child: Text(
              [
                '$students students',
                if (breakdowns!.length > 1)
                  'Composite: ${breakdowns.map((item) => '${item.studentCount} ${item.yearLevelLabel}').join(', ')}',
              ].join(' · '),
              style: AppTypography.footnote.copyWith(color: colors.muted),
            ),
          ),
      ],
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
        title: const Text('Delete classroom'),
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
                  ),
                );

                // Show notification that sign-off was cleared
                if (success) {
                  NotificationUtils.showSignOffClearedNotification(context);
                }
              }
            },
            style: appDestructiveButtonStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
