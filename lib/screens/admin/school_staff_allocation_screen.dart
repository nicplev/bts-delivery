import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/school.dart';
import '../../models/staff.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/staff_providers.dart';
import '../../app/theme/brand_colors.dart';

class SchoolStaffAllocationScreen extends ConsumerStatefulWidget {
  final School school;

  const SchoolStaffAllocationScreen({
    super.key,
    required this.school,
  });

  @override
  ConsumerState<SchoolStaffAllocationScreen> createState() =>
      _SchoolStaffAllocationScreenState();
}

class _SchoolStaffAllocationScreenState
    extends ConsumerState<SchoolStaffAllocationScreen> {
  final Set<String> _selectedStaffIds = {};
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  Widget build(BuildContext context) {
    final staffListAsync = ref.watch(staffListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Staff'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveStaffAllocations,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          // School info header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BrandColors.kakaGreen.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey[300]!,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: BrandColors.kakaGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.school,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.school.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (widget.school.address?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.school.address!,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Select staff members who can access this school',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Staff list
          Expanded(
            child: staffListAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error loading staff: $error'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.invalidate(staffListProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (staffList) {
                if (staffList.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No staff members found',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add staff members first to assign them to schools',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                // Initialize selected staff on first load
                if (_selectedStaffIds.isEmpty && !_hasChanges) {
                  for (final staff in staffList) {
                    if (staff.assignedSchoolIds.contains(widget.school.id)) {
                      _selectedStaffIds.add(staff.id);
                    }
                  }
                }

                // Sort staff: selected first, then by name
                final sortedStaff = List<Staff>.from(staffList)
                  ..sort((a, b) {
                    final aSelected = _selectedStaffIds.contains(a.id);
                    final bSelected = _selectedStaffIds.contains(b.id);
                    if (aSelected && !bSelected) return -1;
                    if (!aSelected && bSelected) return 1;
                    return a.name.compareTo(b.name);
                  });

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedStaff.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final staff = sortedStaff[index];
                    final isSelected = _selectedStaffIds.contains(staff.id);

                    return _StaffSelectionCard(
                      staff: staff,
                      isSelected: isSelected,
                      onChanged: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedStaffIds.add(staff.id);
                          } else {
                            _selectedStaffIds.remove(staff.id);
                          }
                          _hasChanges = true;
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveStaffAllocations() async {
    setState(() => _isLoading = true);

    try {
      final deliveriesRepo = ref.read(deliveriesRepositoryProvider);
      final staffListResult = await deliveriesRepo.getAllStaff();

      await staffListResult.when(
        success: (allStaff) async {
          final changes = <String, bool>{};
          for (final staff in allStaff) {
            final selected = _selectedStaffIds.contains(staff.id);
            if (selected != staff.assignedSchoolIds.contains(widget.school.id)) {
              changes[staff.id] = selected;
            }
          }
          final result = await ref.read(staffRepositoryProvider)
              .setSchoolAssignments(widget.school.id, changes);
          if (result.isFailure) {
            throw Exception(result.errorOrNull);
          }

          // Refresh providers
          ref.invalidate(staffListProvider);

          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasChanges = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Staff assignments saved successfully'),
                backgroundColor: Colors.green,
              ),
            );

            // Go back to schools list
            context.pop();
          }
        },
        failure: (message, _) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save: $message'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _StaffSelectionCard extends StatelessWidget {
  final Staff staff;
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  const _StaffSelectionCard({
    required this.staff,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? BrandColors.kakaGreen : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!isSelected),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Checkbox
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color:
                      isSelected ? BrandColors.kakaGreen : Colors.transparent,
                  border: Border.all(
                    color:
                        isSelected ? BrandColors.kakaGreen : Colors.grey[400]!,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Staff avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: isSelected
                    ? BrandColors.kakaGreen.withValues(alpha: 0.2)
                    : Colors.grey[200],
                child: Icon(
                  staff.isAdmin
                      ? Icons.admin_panel_settings
                      : staff.isManager
                          ? Icons.supervisor_account
                          : Icons.person,
                  size: 20,
                  color: isSelected ? BrandColors.kakaGreen : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 12),

              // Staff info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isSelected ? BrandColors.textPrimary : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: staff.isAdmin
                                ? BrandColors.kakaPink.withValues(alpha: 0.1)
                                : staff.isManager
                                    ? BrandColors.kakaBlue
                                        .withValues(alpha: 0.1)
                                    : Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            staff.isAdmin
                                ? 'Admin'
                                : staff.isManager
                                    ? 'Manager'
                                    : 'Staff',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: staff.isAdmin
                                  ? BrandColors.kakaPink
                                  : staff.isManager
                                      ? BrandColors.kakaBlue
                                      : Colors.grey[700],
                            ),
                          ),
                        ),
                        if (staff.assignedSchoolIds.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${staff.assignedSchoolIds.length} ${staff.assignedSchoolIds.length == 1 ? 'school' : 'schools'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[800],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Selection indicator
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: BrandColors.kakaGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: BrandColors.kakaGreen,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
