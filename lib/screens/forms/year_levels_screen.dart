import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/delivery_visit.dart';
import '../../models/school.dart';
import '../../providers/auth_providers.dart';
import '../../providers/delivery_visit_provider.dart';
import '../../providers/schools_providers.dart';
import '../../widgets/design/design.dart';

/// Year levels in school order: Prep, Year 1 … Year 6, then everything else
/// (specialist, composite, unknown) in their saved order.
List<YearLevel> sortYearLevels(Iterable<YearLevel> levels) {
  final indexed = levels.toList().asMap().entries.toList();
  int rank(YearLevel level) =>
      SchoolYear.parse(level.label)?.index ?? SchoolYear.values.length;
  indexed.sort((a, b) {
    final byYear = rank(a.value).compareTo(rank(b.value));
    return byYear != 0 ? byYear : a.key.compareTo(b.key);
  });
  return [for (final entry in indexed) entry.value];
}

/// Opens the per-year classrooms list (add / rename / delete classrooms).
void openYearLevelClassrooms(
  BuildContext context,
  WidgetRef ref,
  String schoolId,
  String yearLevelId,
) {
  context.push(schoolWorkPath(
    schoolId,
    visit: ref.read(activeDeliveryVisitProvider),
    suffix: '/year/${Uri.encodeComponent(yearLevelId)}/classrooms',
  ));
}

/// Glass sheet listing the school's year levels; choosing one opens its
/// classrooms. Editors can also add a year level from here.
Future<void> showManageClassroomsSheet(
  BuildContext context,
  WidgetRef ref,
  String schoolId,
) {
  // Sheets live on the root navigator, outside this page's provider scope
  // (the visit workspace). Carry the scope over so the same streams are used.
  final container = ProviderScope.containerOf(context);
  final canEdit = ref.read(canEditSchoolDataProvider);
  return showAppGlassSheet<void>(
    context: context,
    title: 'Manage classrooms',
    builder: (sheetContext) => UncontrolledProviderScope(
      container: container,
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Choose a year level to add, rename or delete its classrooms.',
              style: AppTypography.subheadline
                  .copyWith(color: AppPalette.of(sheetContext).muted),
            ),
          ),
          YearLevelsList(
            schoolId: schoolId,
            onOpen: (level) {
              Navigator.of(sheetContext).pop();
              if (context.mounted) {
                openYearLevelClassrooms(context, ref, schoolId, level.id);
              }
            },
          ),
          if (canEdit) ...[
            const SizedBox(height: 16),
            AppSecondaryButton(
              key: const ValueKey('manage-add-year-level'),
              label: 'Add year level',
              icon: AppIcons.add,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                if (context.mounted) {
                  showAddYearLevelDialog(context, ref, schoolId);
                }
              },
            ),
          ],
        ],
      ),
    ),
  );
}

/// The year levels of a school as badge rows with their classroom count.
class YearLevelsList extends ConsumerWidget {
  const YearLevelsList({
    super.key,
    required this.schoolId,
    required this.onOpen,
  });

  final String schoolId;
  final ValueChanged<YearLevel> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yearLevelsAsync = ref.watch(yearLevelsProvider(schoolId));
    return yearLevelsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => AppNotice(
        icon: AppIcons.error,
        message: 'Couldn’t load year levels',
        trailing: AppSecondaryButton(
          label: 'Retry',
          expand: false,
          large: false,
          onPressed: () => ref.invalidate(yearLevelsProvider(schoolId)),
        ),
      ),
      data: (levels) {
        if (levels.isEmpty) {
          return const AppNotice(message: 'No year levels found');
        }
        return AppGroupedList(
          separatorIndent: 64,
          children: [
            for (final level in sortYearLevels(levels))
              _YearLevelRow(
                schoolId: schoolId,
                level: level,
                onTap: () => onOpen(level),
              ),
          ],
        );
      },
    );
  }
}

class _YearLevelRow extends ConsumerWidget {
  const _YearLevelRow({
    required this.schoolId,
    required this.level,
    required this.onTap,
  });

  final String schoolId;
  final YearLevel level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classrooms = ref
        .watch(classroomsProvider((schoolId: schoolId, yearLevelId: level.id)));
    return AppListRow(
      key: ValueKey('year-level-${level.id}'),
      leading: AppYearBadge(label: level.label),
      title: level.label,
      subtitle: classrooms.when(
        loading: () => 'Loading classrooms…',
        error: (_, __) => 'Error loading classrooms',
        data: (rooms) =>
            '${rooms.length} classroom${rooms.length != 1 ? 's' : ''}',
      ),
      onTap: onTap,
    );
  }
}

/// Year levels of a school (also reachable as the "Manage classrooms" sheet
/// from the visit hub).
class YearLevelsScreen extends ConsumerWidget {
  const YearLevelsScreen({super.key, required this.schoolId});

  final String schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canEditSchoolDataProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppNavBar(),
      body: AppFloatingActionArea(
        action: canEdit
            ? AppGlassPrimaryButton(
                label: 'Add year level',
                icon: AppIcons.add,
                onPressed: () => showAddYearLevelDialog(context, ref, schoolId),
              )
            : null,
        child: Builder(
          builder: (context) => ListView(
            padding: AppInsets.scroll(context),
            children: [
              const AppLargeTitle(title: 'Year levels'),
              const SizedBox(height: AppTokens.sectionGap),
              YearLevelsList(
                schoolId: schoolId,
                onOpen: (level) =>
                    openYearLevelClassrooms(context, ref, schoolId, level.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Add year level" dialog (editors).
void showAddYearLevelDialog(
  BuildContext context,
  WidgetRef ref,
  String schoolId,
) {
  final controller = TextEditingController();

  showDialog(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add year level'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Year level name',
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

/// "Edit year level" (rename) dialog (editors).
void showEditYearLevelDialog(
  BuildContext context,
  WidgetRef ref,
  String schoolId,
  YearLevel yearLevel,
) {
  final nameController = TextEditingController(text: yearLevel.label);
  final formKey = GlobalKey<FormState>();

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit year level'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Year level name',
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

/// "Delete year level" confirmation (editors). [onDeleted] runs after a
/// successful delete (e.g. to leave the deleted year's screen).
void showDeleteYearLevelDialog(
  BuildContext context,
  WidgetRef ref,
  String schoolId,
  YearLevel yearLevel, {
  VoidCallback? onDeleted,
}) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete year level'),
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

            final messenger = ScaffoldMessenger.of(context);
            final success = await ref
                .read(schoolsNotifierProvider.notifier)
                .deleteYearLevel(schoolId, yearLevel.id);

            messenger.showSnackBar(
              SnackBar(
                content: Text(success
                    ? 'Year level deleted successfully'
                    : 'Failed to delete year level'),
              ),
            );
            if (success) onDeleted?.call();
          },
          style: appDestructiveButtonStyle(context),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
