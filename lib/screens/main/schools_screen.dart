import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/schools_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/repository_providers.dart';
import '../../models/school.dart';
import '../../app/theme/brand_colors.dart';

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
        error: (error, _) => const Center(child: CircularProgressIndicator()),
        data: (staff) {
          // If user is not linked to staff and not an admin, show placeholder
          if (staff == null && !isAdmin) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.link_off,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Account Not Linked',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your account needs to be linked to a staff member to access schools.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.go('/staff-link'),
                      icon: const Icon(Icons.link),
                      label: const Text('Link Account'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.go('/profile'),
                      child: const Text('Go to Profile'),
                    ),
                  ],
                ),
              ),
            );
          }

          // User is linked or is admin, show schools
          return schoolsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error loading schools: $error'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(schoolsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (schools) {
              if (schools.isEmpty) {
                // Different messages based on role
                if (isAdmin) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.school_outlined,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No schools found'),
                        SizedBox(height: 8),
                        Text(
                          'Tap the + button to add your first school',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                } else if (staff?.hasManagerAccess ?? false) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.school_outlined,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No schools found'),
                        SizedBox(height: 8),
                        Text(
                          'Contact an admin to add schools',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                } else {
                  // Regular staff with no assigned schools
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'No Schools Assigned',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'You don\'t have any schools assigned to you yet. Contact your manager or admin to get assigned to schools.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextButton.icon(
                            onPressed: () => context.go('/profile'),
                            icon: const Icon(Icons.person),
                            label: const Text('View Profile'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              }

              // Filter schools based on search query
              final filteredSchools = _filterSchools(schools);
              final showSearchBar =
                  schools.length > 5; // Show search if more than 5 schools

              return Column(
                children: [
                  // Search bar
                  if (showSearchBar)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search schools by name or address...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),

                  // Results count
                  if (showSearchBar && _searchQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            '${filteredSchools.length} of ${schools.length} schools',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // School list or no results message
                  Expanded(
                    child: filteredSchools.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off,
                                    size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'No schools found',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try a different search term',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Clear Search'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: filteredSchools.length,
                            itemBuilder: (context, index) {
                              final school = filteredSchools[index];
                              return _SchoolCard(
                                school: school,
                                searchQuery: _searchQuery,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
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
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                failure: (message, _) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: Colors.red,
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/schools/${school.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.school,
                    color: searchQuery.isNotEmpty &&
                            school.name
                                .toLowerCase()
                                .contains(searchQuery.toLowerCase())
                        ? BrandColors.kakaBlue
                        : Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      school.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (isAdmin)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 8,
                      offset: const Offset(0, 8),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _showEditSchoolDialog(context, ref, school);
                            break;
                          case 'staff':
                            context.push(
                                '/schools/${school.id}/staff-allocation',
                                extra: school);
                            break;
                          case 'delete':
                            _showDeleteDialog(context, ref, school);
                            break;
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
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Edit',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'staff',
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 20,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Manage Staff',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    const Icon(Icons.arrow_forward_ios,
                        size: 16, color: Colors.grey),
                ],
              ),
              if (school.address?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 36), // Align with school name
                    Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        school.address!,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                failure: (message, _) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: Colors.red,
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
                  color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
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
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                failure: (message, _) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
