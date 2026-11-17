import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/schools_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/repository_providers.dart';
import '../../models/school.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';
import '../admin/admin_page.dart';

enum _AddChoice { add, bulk }

enum _SchoolChoice { edit, staff, delete }

class SchoolsScreen extends ConsumerStatefulWidget {
  const SchoolsScreen({super.key});

  @override
  ConsumerState<SchoolsScreen> createState() => _SchoolsScreenState();
}

class _SchoolsScreenState extends ConsumerState<SchoolsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<School> _filterSchools(List<School> schools) {
    if (_searchQuery.isEmpty) return schools;

    final query = _searchQuery.toLowerCase();
    return schools.where((school) {
      final nameMatch = school.name.toLowerCase().contains(query);
      final addressMatch =
          school.address?.toLowerCase().contains(query) ?? false;
      return nameMatch || addressMatch;
    }).toList();
  }

  Future<void> _showAddOptions() async {
    final choice = await showAdminActionSheet<_AddChoice>(
      context,
      title: 'Add schools',
      actions: const [
        AdminSheetAction(
            value: _AddChoice.add, label: 'Add school', icon: AppIcons.add),
        AdminSheetAction(
            value: _AddChoice.bulk,
            label: 'Bulk import CSV',
            icon: AppIcons.importFile),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _AddChoice.add:
        _showSchoolDialog(context, ref);
      case _AddChoice.bulk:
        context.push('/schools/bulk-import');
    }
  }

  @override
  Widget build(BuildContext context) {
    final schoolsAsync = ref.watch(schoolsProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final currentStaffAsync = ref.watch(currentStaffProvider);

    String? subtitle;
    final List<Widget> content = currentStaffAsync.when(
      loading: () => const [AdminLoading()],
      error: (_, __) => [
        DeliveryMessage(
          icon: AppIcons.error,
          title: 'Couldn’t load your staff account',
          action: AppSecondaryButton(
            label: 'Retry',
            icon: AppIcons.retry,
            onPressed: () => ref.invalidate(currentStaffProvider),
          ),
        ),
      ],
      data: (staff) {
        if (staff == null && !isAdmin) {
          return [
            DeliveryMessage(
              icon: HeroiconsOutline.link,
              title: 'Account not linked',
              description: 'Link your staff account to see your schools.',
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  AppPrimaryButton(
                    label: 'Link account',
                    icon: HeroiconsOutline.link,
                    onPressed: () => context.go('/staff-link'),
                  ),
                  AppSecondaryButton(
                    label: 'Go to profile',
                    onPressed: () => context.go('/profile'),
                  ),
                ],
              ),
            ),
          ];
        }

        return schoolsAsync.when(
          loading: () => const [AdminLoading()],
          error: (_, __) => [
            DeliveryMessage(
              icon: AppIcons.error,
              title: 'Couldn’t load schools',
              action: AppSecondaryButton(
                label: 'Retry',
                icon: AppIcons.retry,
                onPressed: () => ref.invalidate(schoolsProvider),
              ),
            ),
          ],
          data: (schools) {
            if (schools.isEmpty) {
              final canBrowseAll =
                  isAdmin || (staff?.hasManagerAccess ?? false);
              return [
                DeliveryMessage(
                  icon: AppIcons.school,
                  title:
                      canBrowseAll ? 'No schools found' : 'No schools assigned',
                  description: isAdmin
                      ? 'Use Add school to create the first school.'
                      : canBrowseAll
                          ? 'Contact an administrator to add schools.'
                          : 'Ask your manager or administrator to assign a school.',
                  action: canBrowseAll
                      ? null
                      : AppSecondaryButton(
                          label: 'View profile',
                          onPressed: () => context.go('/profile'),
                        ),
                ),
              ];
            }
            final results = _filterSchools(schools);
            subtitle = _searchQuery.isNotEmpty
                ? '${results.length} of ${schools.length} schools'
                : '${schools.length} ${schools.length == 1 ? 'school' : 'schools'}';
            return _buildDirectory(schools, results, isAdmin);
          },
        );
      },
    );

    return AdminPage(
      title: 'Schools',
      subtitle: subtitle,
      showBack: false,
      navActions: [
        if (isAdmin)
          AppGlassIconButton(
            icon: AppIcons.add,
            semanticLabel: 'Add school',
            onPressed: _showAddOptions,
          ),
      ],
      children: content,
    );
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
  }

  List<Widget> _buildDirectory(
      List<School> schools, List<School> results, bool isAdmin) {
    final colors = AppPalette.of(context);
    return [
      if (schools.length > 5) ...[
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search by name or address',
            prefixIcon: Icon(AppIcons.search, size: 20, color: colors.muted),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: Icon(HeroiconsSolid.xCircle,
                        size: 20, color: colors.muted),
                    onPressed: _clearSearch,
                  )
                : null,
            fillColor: colors.fill,
            border: _searchBorder,
            enabledBorder: _searchBorder,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
        const SizedBox(height: 16),
      ],
      if (results.isEmpty)
        DeliveryMessage(
          icon: AppIcons.search,
          title: 'No schools found',
          description: 'Try a different search term.',
          action: AppSecondaryButton(
            label: 'Clear search',
            onPressed: _clearSearch,
          ),
        )
      else
        AppGroupedList(
          separatorIndent: 57,
          children: [
            for (final school in results)
              _SchoolRow(
                key: ValueKey(school.id),
                school: school,
                isAdmin: isAdmin,
              ),
          ],
        ),
    ];
  }

  static const _searchBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppTokens.controlRadius)),
    borderSide: BorderSide.none,
  );

  void _showSchoolDialog(BuildContext context, WidgetRef ref) {
    _showSchoolFormDialog(
      context,
      title: 'Add school',
      submitLabel: 'Add',
      onSubmit: (name, address) async {
        final schoolsRepo = ref.read(schoolsRepositoryProvider);
        final newSchool = School(
          id: '',
          name: name,
          address: address,
          createdAt: DateTime.now(),
        );

        final result = await schoolsRepo.createSchool(newSchool);

        result.when(
          success: (_) {
            ref.invalidate(schoolsProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('School added successfully')),
              );
            }
          },
          failure: (message, _) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            }
          },
        );
      },
    );
  }
}

/// Add / edit school form. [onSubmit] gets the trimmed name and the address
/// (null when empty) after the dialog closes.
void _showSchoolFormDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  School? school,
  required Future<void> Function(String name, String? address) onSubmit,
}) {
  final nameController = TextEditingController(text: school?.name ?? '');
  final addressController = TextEditingController(text: school?.address ?? '');
  final formKey = GlobalKey<FormState>();

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'School name',
                hintText: 'e.g., Brighton Primary School',
                prefixIcon: Icon(AppIcons.school, size: 20),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a school name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                hintText: 'e.g., 123 Main St, Brighton',
                prefixIcon: Icon(AppIcons.location, size: 20),
              ),
              textCapitalization: TextCapitalization.words,
              maxLines: 2,
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
            if (!formKey.currentState!.validate()) return;

            Navigator.of(dialogContext).pop();
            final address = addressController.text.trim();
            await onSubmit(
              nameController.text.trim(),
              address.isEmpty ? null : address,
            );
          },
          child: Text(submitLabel),
        ),
      ],
    ),
  );
}

class _SchoolRow extends ConsumerWidget {
  const _SchoolRow({super.key, required this.school, required this.isAdmin});

  final School school;
  final bool isAdmin;

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final choice = await showAdminActionSheet<_SchoolChoice>(
      context,
      title: school.name,
      actions: const [
        AdminSheetAction(
            value: _SchoolChoice.edit, label: 'Edit', icon: AppIcons.edit),
        AdminSheetAction(
            value: _SchoolChoice.staff,
            label: 'Manage staff',
            icon: AppIcons.people),
        AdminSheetAction(
            value: _SchoolChoice.delete,
            label: 'Delete',
            icon: AppIcons.delete,
            destructive: true),
      ],
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case _SchoolChoice.edit:
        _showEditSchoolDialog(context, ref);
      case _SchoolChoice.staff:
        context.push('/schools/${school.id}/staff-allocation', extra: school);
      case _SchoolChoice.delete:
        _showDeleteDialog(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = school.address?.isNotEmpty == true ? school.address : null;
    return AppListRow(
      icon: AppIcons.school,
      title: school.name,
      subtitle: address,
      titleStyle:
          AppTypography.headline.copyWith(color: AppPalette.of(context).ink),
      onTap: () => context.push('/schools/${school.id}'),
      showChevron: !isAdmin,
      trailing: isAdmin
          ? AdminOptionsButton(
              semanticLabel: 'Manage school',
              onPressed: () => _showOptions(context, ref),
            )
          : null,
    );
  }

  void _showEditSchoolDialog(BuildContext context, WidgetRef ref) {
    _showSchoolFormDialog(
      context,
      title: 'Edit school',
      submitLabel: 'Save',
      school: school,
      onSubmit: (name, address) async {
        final schoolsRepo = ref.read(schoolsRepositoryProvider);
        final updatedSchool = school.copyWith(name: name, address: address);

        final result = await schoolsRepo.updateSchool(updatedSchool);

        result.when(
          success: (_) {
            ref.invalidate(schoolsProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('School updated successfully')),
              );
            }
          },
          failure: (message, _) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            }
          },
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    final colors = AppPalette.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Delete school'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${school.name}"?'),
            const SizedBox(height: 8),
            Text(
              'Warning: This will delete all associated data including year levels, classrooms, deliveries, and records.',
              style: AppTypography.subheadline.copyWith(color: colors.muted),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: AppTypography.subheadline
                  .copyWith(color: colors.error, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              final schoolsRepo = ref.read(schoolsRepositoryProvider);
              final result = await schoolsRepo.deleteSchool(school.id);

              result.when(
                success: (_) {
                  ref.invalidate(schoolsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('School deleted successfully')),
                    );
                  }
                },
                failure: (message, _) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  }
                },
              );
            },
            style: adminDestructiveStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
