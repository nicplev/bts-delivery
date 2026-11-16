import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/school.dart';
import '../../models/staff.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/staff_providers.dart';
import '../../app/theme/brand_colors.dart';
import '../../widgets/design/design.dart';

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
      body: SafeArea(
        top: false,
        child: staffListAsync.when(
          loading: () => _statusList(
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
          error: (error, _) => _statusList(
            AppPanel(
              tone: AppTone.pink,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Error loading staff: $error'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => ref.invalidate(staffListProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (staffList) {
            if (staffList.isEmpty) {
              return _statusList(
                const AppPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSectionHeading(title: 'No staff members found'),
                      SizedBox(height: 8),
                      Text('Add staff members first to assign them to schools'),
                    ],
                  ),
                ),
              );
            }
            if (_selectedStaffIds.isEmpty && !_hasChanges) {
              for (final staff in staffList) {
                if (staff.assignedSchoolIds.contains(widget.school.id)) {
                  _selectedStaffIds.add(staff.id);
                }
              }
            }
            final sortedStaff = List<Staff>.from(staffList)
              ..sort((a, b) {
                final aSelected = _selectedStaffIds.contains(a.id);
                final bSelected = _selectedStaffIds.contains(b.id);
                if (aSelected && !bSelected) return -1;
                if (!aSelected && bSelected) return 1;
                return a.name.compareTo(b.name);
              });

            return ListView.separated(
              padding: _pagePadding,
              itemCount: sortedStaff.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) return _schoolHeader(context);
                final staff = sortedStaff[index - 1];
                return _StaffSelectionCard(
                  staff: staff,
                  isSelected: _selectedStaffIds.contains(staff.id),
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
    );
  }

  static const _pagePadding = EdgeInsets.fromLTRB(
      AppTokens.gutter, 10, AppTokens.gutter, AppTokens.sectionGap);

  Widget _statusList(Widget state) => ListView(
        padding: _pagePadding,
        children: [
          _schoolHeader(context),
          const SizedBox(height: 12),
          state,
        ],
      );

  Widget _schoolHeader(BuildContext context) => AppPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppIconTile(icon: Icons.school_outlined, tone: AppTone.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.school.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  if (widget.school.address?.isNotEmpty == true)
                    Text(widget.school.address!),
                  const SizedBox(height: 6),
                  const Text('Select staff members who can access this school'),
                ],
              ),
            ),
          ],
        ),
      );

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
            if (selected !=
                staff.assignedSchoolIds.contains(widget.school.id)) {
              changes[staff.id] = selected;
            }
          }
          final result = await ref
              .read(staffRepositoryProvider)
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
                backgroundColor: BrandColors.greenDarker,
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
                backgroundColor: BrandColors.pinkDarker,
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
            backgroundColor: BrandColors.pinkDarker,
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
    final role = staff.isAdmin
        ? 'Admin'
        : staff.isManager
            ? 'Manager'
            : 'Staff';
    final tone = staff.isAdmin
        ? AppTone.pink
        : staff.isManager
            ? AppTone.blue
            : AppTone.neutral;
    final assignments = staff.assignedSchoolIds.length;
    return AppPanel(
      padding: EdgeInsets.zero,
      tone: isSelected ? AppTone.green : null,
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (value) => onChanged(value ?? false),
        title: Text(staff.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AppStatusPill(label: role, tone: tone),
              if (assignments > 0)
                AppStatusPill(
                  label:
                      '$assignments ${assignments == 1 ? 'school' : 'schools'}',
                ),
            ],
          ),
        ),
        secondary: AppIconTile(
          icon: staff.isAdmin
              ? Icons.admin_panel_settings_outlined
              : staff.isManager
                  ? Icons.supervisor_account_outlined
                  : Icons.person_outline,
          tone: tone,
        ),
      ),
    );
  }
}
