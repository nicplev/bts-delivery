import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/schools_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/repository_providers.dart';
import '../../models/school.dart';
import '../../app/theme/brand_colors.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';

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

  @override
  Widget build(BuildContext context) {
    final schoolsAsync = ref.watch(schoolsProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final currentStaffAsync = ref.watch(currentStaffProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schools'),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.add),
              tooltip: 'Add School',
              onSelected: (value) {
                switch (value) {
                  case 'add':
                    _showAddSchoolDialog(context, ref);
                    break;
                  case 'bulk':
                    context.push('/schools/bulk-import');
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'add',
                  child: Row(
                    children: [
                      Icon(Icons.add),
                      SizedBox(width: 8),
                      Text('Add School'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'bulk',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file),
                      SizedBox(width: 8),
                      Text('Bulk Import CSV'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: currentStaffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: DeliveryMessage(
            icon: Icons.error_outline,
            title: 'Couldn’t load your staff account',
            action: TextButton(
              onPressed: () => ref.invalidate(currentStaffProvider),
              child: const Text('Retry'),
            ),
          ),
        ),
        data: (staff) {
          if (staff == null && !isAdmin) {
            return Center(
              child: DeliveryMessage(
                icon: Icons.link_off,
                title: 'Account not linked',
                description: 'Link your staff account to see your schools.',
                action: Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => context.go('/staff-link'),
                      icon: const Icon(Icons.link),
                      label: const Text('Link Account'),
                    ),
                    TextButton(
                      onPressed: () => context.go('/profile'),
                      child: const Text('Go to Profile'),
                    ),
                  ],
                ),
              ),
            );
          }

          return schoolsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: DeliveryMessage(
                icon: Icons.error_outline,
                title: 'Couldn’t load schools',
                action: TextButton(
                  onPressed: () => ref.invalidate(schoolsProvider),
                  child: const Text('Retry'),
                ),
              ),
            ),
            data: (schools) {
              if (schools.isEmpty) {
                final canBrowseAll =
                    isAdmin || (staff?.hasManagerAccess ?? false);
                return Center(
                  child: DeliveryMessage(
                    icon: Icons.school_outlined,
                    title: canBrowseAll
                        ? 'No schools found'
                        : 'No schools assigned',
                    description: isAdmin
                        ? 'Use Add School to create the first school.'
                        : canBrowseAll
                            ? 'Contact an administrator to add schools.'
                            : 'Ask your manager or administrator to assign a school.',
                    action: canBrowseAll
                        ? null
                        : TextButton(
                            onPressed: () => context.go('/profile'),
                            child: const Text('View Profile'),
                          ),
                  ),
                );
              }
              return _buildDirectory(schools);
            },
          );
        },
      ),
    );
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
  }

  Widget _buildDirectory(List<School> schools) {
    final results = _filterSchools(schools);
    final showSearch = schools.length > 5;
    final count = _searchQuery.isNotEmpty
        ? '${results.length} of ${schools.length} schools'
        : '${schools.length} ${schools.length == 1 ? 'school' : 'schools'}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.gutter,
                  8,
                  AppTokens.gutter,
                  12,
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or address',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _clearSearch,
                          )
                        : null,
                    fillColor: AppTokens.surface,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.gutter,
                8,
                AppTokens.gutter,
                12,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppStatusPill(
                  label: count,
                  icon: Icons.school_outlined,
                  tone: AppTone.green,
                ),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: DeliveryMessage(
                        icon: Icons.search_off_rounded,
                        title: 'No schools found',
                        description: 'Try a different search term.',
                        action: TextButton(
                          onPressed: _clearSearch,
                          child: const Text('Clear Search'),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppTokens.gutter,
                        2,
                        AppTokens.gutter,
                        16,
                      ),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _SchoolCard(
                        school: results[index],
                        searchQuery: _searchQuery,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSchoolDialog(BuildContext context, WidgetRef ref) {
    _showSchoolDialog(context, ref, null);
  }

  void _showSchoolDialog(BuildContext context, WidgetRef ref, School? school) {
    final nameController = TextEditingController(text: school?.name ?? '');
    final addressController =
        TextEditingController(text: school?.address ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(school == null ? 'Add School' : 'Edit School'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'School Name',
                  hintText: 'e.g., Brighton Primary School',
                  prefixIcon: Icon(Icons.school),
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
                  labelText: 'Address (Optional)',
                  hintText: 'e.g., 123 Main St, Brighton',
                  prefixIcon: Icon(Icons.location_on),
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

              final schoolsRepo = ref.read(schoolsRepositoryProvider);
              final newSchool = School(
                id: school?.id ?? '',
                name: nameController.text.trim(),
                address: addressController.text.trim().isEmpty
                    ? null
                    : addressController.text.trim(),
                createdAt: school?.createdAt ?? DateTime.now(),
              );

              final result = school == null
                  ? await schoolsRepo.createSchool(newSchool)
                  : await schoolsRepo.updateSchool(newSchool);

              result.when(
                success: (_) {
                  ref.invalidate(schoolsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(school == null
                            ? 'School added successfully'
                            : 'School updated successfully'),
                        backgroundColor: BrandColors.greenDarker,
                      ),
                    );
                  }
                },
                failure: (message, _) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: BrandColors.pinkDarker,
                      ),
                    );
                  }
                },
              );
            },
            child: Text(school == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _SchoolCard extends ConsumerWidget {
  const _SchoolCard({required this.school, this.searchQuery = ''});

  final School school;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    final matchingName = searchQuery.isNotEmpty &&
        school.name.toLowerCase().contains(searchQuery.toLowerCase());

    return AppPanel(
      onTap: () => context.push('/schools/${school.id}'),
      child: Row(
        children: [
          AppIconTile(
            icon: Icons.school_outlined,
            tone: matchingName ? AppTone.blue : AppTone.green,
            size: 46,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(school.name,
                    style: Theme.of(context).textTheme.titleMedium),
                if (school.address?.isNotEmpty == true) ...[
                  const SizedBox(height: 5),
                  Text(school.address!,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (isAdmin)
            PopupMenuButton<String>(
              tooltip: 'Manage school',
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _showEditSchoolDialog(context, ref, school);
                  case 'staff':
                    context.push('/schools/${school.id}/staff-allocation',
                        extra: school);
                  case 'delete':
                    _showDeleteDialog(context, ref, school);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'staff', child: Text('Manage Staff')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete',
                      style: TextStyle(color: BrandColors.pinkDarker)),
                ),
              ],
            )
          else
            const Icon(Icons.chevron_right_rounded, color: AppTokens.muted),
        ],
      ),
    );
  }

  void _showEditSchoolDialog(
      BuildContext context, WidgetRef ref, School school) {
    final nameController = TextEditingController(text: school.name);
    final addressController = TextEditingController(text: school.address ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit School'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'School Name',
                  prefixIcon: Icon(Icons.school),
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
                  labelText: 'Address (Optional)',
                  prefixIcon: Icon(Icons.location_on),
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

              final schoolsRepo = ref.read(schoolsRepositoryProvider);
              final updatedSchool = school.copyWith(
                name: nameController.text.trim(),
                address: addressController.text.trim().isEmpty
                    ? null
                    : addressController.text.trim(),
              );

              final result = await schoolsRepo.updateSchool(updatedSchool);

              result.when(
                success: (_) {
                  ref.invalidate(schoolsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('School updated successfully'),
                        backgroundColor: BrandColors.greenDarker,
                      ),
                    );
                  }
                },
                failure: (message, _) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: BrandColors.pinkDarker,
                      ),
                    );
                  }
                },
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, School school) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete School'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${school.name}"?'),
            const SizedBox(height: 8),
            const Text(
              'Warning: This will delete all associated data including year levels, classrooms, deliveries, and records.',
              style: TextStyle(color: BrandColors.kakaBlue, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(
                  color: BrandColors.pinkDarker,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
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
                        content: Text('School deleted successfully'),
                        backgroundColor: BrandColors.greenDarker,
                      ),
                    );
                  }
                },
                failure: (message, _) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: BrandColors.pinkDarker,
                      ),
                    );
                  }
                },
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.pinkDarker,
              foregroundColor: AppTokens.surface,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
