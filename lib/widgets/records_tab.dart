import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/schools_providers.dart';
import '../providers/auth_providers.dart';
import '../models/school.dart';
import '../models/delivery_visit.dart';
import '../providers/delivery_visit_provider.dart';
import 'delivery_day_list.dart';
import 'design/design.dart';

class RecordsTab extends ConsumerWidget {
  const RecordsTab({super.key, required this.schoolId});

  final String schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yearLevelsAsync = ref.watch(yearLevelsProvider(schoolId));

    return CustomScrollView(
      key: const PageStorageKey('school-records'),
      primary: true,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.gutter,
            16,
            AppTokens.gutter,
            8,
          ),
          sliver: SliverToBoxAdapter(
            child: AppSectionHeading(
              title: 'Year Levels',
              trailing: ref.watch(canEditSchoolDataProvider)
                  ? IconButton(
                      onPressed: () => _showAddYearLevelDialog(context, ref),
                      icon: const Icon(Icons.add),
                      tooltip: 'Add Year Level',
                    )
                  : null,
            ),
          ),
        ),
        yearLevelsAsync.when(
          loading: () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: DeliveryMessage(
                icon: Icons.error_outline,
                title: 'Couldn’t load year levels',
                action: TextButton(
                  onPressed: () => ref.invalidate(yearLevelsProvider(schoolId)),
                  child: const Text('Retry'),
                ),
              ),
            ),
          ),
          data: (yearLevels) {
            if (yearLevels.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: DeliveryMessage(
                    icon: Icons.class_outlined,
                    title: 'No year levels found',
                  ),
                ),
              );
            }

            return SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppTokens.gutter,
                0,
                AppTokens.gutter,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              sliver: SliverList.builder(
                itemCount: yearLevels.length,
                itemBuilder: (context, index) => _YearLevelCard(
                  schoolId: schoolId,
                  yearLevel: yearLevels[index],
                ),
              ),
            );
          },
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
    final backgroundColor =
        YearLevelColors.getBackgroundColor(context, yearLevel.label);
    final iconColor = YearLevelColors.getIconColor(context, yearLevel.label);
    final needsBorder = YearLevelColors.needsBorder(yearLevel.label);

    return AppPanel(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(schoolWorkPath(
        schoolId,
        visit: ref.read(activeDeliveryVisitProvider),
        suffix: '/year/${Uri.encodeComponent(yearLevel.id)}/classrooms',
      )),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: needsBorder
                  ? Border.all(color: AppPalette.of(context).outline)
                  : null,
            ),
            child: Icon(Icons.class_outlined, size: 21, color: iconColor),
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
                  loading: () => Text('Loading classrooms...',
                      style: TextStyle(color: AppPalette.of(context).muted)),
                  error: (_, __) => Text('Error loading classrooms',
                      style: TextStyle(color: AppTone.pink.inkFor(context))),
                  data: (classrooms) => Text(
                    '${classrooms.length} classroom${classrooms.length != 1 ? 's' : ''}',
                    style: TextStyle(color: AppPalette.of(context).muted),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: AppPalette.of(context).muted,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppPalette.of(context).ink,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppPalette.of(context).error,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppPalette.of(context).error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Icon(Icons.chevron_right, color: AppPalette.of(context).muted),
        ],
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
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
