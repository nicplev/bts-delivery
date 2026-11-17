import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/school.dart';
import '../../models/staff.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/staff_providers.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';
import 'admin_page.dart';

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

    final List<Widget> content = staffListAsync.when(
      loading: () => const [AdminLoading()],
      error: (error, _) => [
        DeliveryMessage(
          icon: AppIcons.error,
          title: 'Error loading staff: $error',
          action: AppSecondaryButton(
            label: 'Retry',
            icon: AppIcons.retry,
            onPressed: () => ref.invalidate(staffListProvider),
          ),
        ),
      ],
      data: (staffList) {
        if (staffList.isEmpty) {
          return const [
            DeliveryMessage(
              icon: AppIcons.people,
              title: 'No staff members found',
              description: 'Add staff members first to assign them to schools',
            ),
          ];
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

        return [
          AdminSection(
            label: 'Staff · ${_selectedStaffIds.length} selected',
            child: AppGroupedList(
              separatorIndent: 57,
              children: [
                for (final staff in sortedStaff)
                  _StaffSelectionRow(
                    key: ValueKey(staff.id),
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
                  ),
              ],
            ),
          ),
        ];
      },
    );

    return AdminPage(
      title: 'Manage staff',
      subtitle: 'Select staff members who can access this school',
      action: _hasChanges
          ? AppGlassPrimaryButton(
              label: 'Save',
              icon: AppIcons.check,
              loading: _isLoading,
              onPressed: _saveStaffAllocations,
            )
          : null,
      children: [
        AdminSection(
          first: true,
          label: 'School',
          child: _schoolHeader(context),
        ),
        const SizedBox(height: AppTokens.sectionGap),
        ...content,
      ],
    );
  }

  Widget _schoolHeader(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppIconTile(icon: AppIcons.school),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.school.name,
                    style: AppTypography.headline.copyWith(color: colors.ink)),
                if (widget.school.address?.isNotEmpty == true)
                  Text(widget.school.address!,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted)),
              ],
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
          ),
        );
      }
    }
  }
}

/// A staff member with a checkbox: role icon tile, name and neutral pills for
/// the role and how many schools they already cover.
class _StaffSelectionRow extends StatelessWidget {
  final Staff staff;
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  const _StaffSelectionRow({
    super.key,
    required this.staff,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final role = staff.isAdmin
        ? 'Admin'
        : staff.isManager
            ? 'Manager'
            : 'Staff';
    final assignments = staff.assignedSchoolIds.length;
    return CheckboxListTile(
      value: isSelected,
      onChanged: (value) => onChanged(value ?? false),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      title: Text(staff.name,
          style: AppTypography.headline.copyWith(color: colors.ink)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            AppStatusPill(label: role),
            if (assignments > 0)
              AppStatusPill(
                label:
                    '$assignments ${assignments == 1 ? 'school' : 'schools'}',
              ),
          ],
        ),
      ),
      secondary: AppIconTile(
        size: 29,
        icon: staff.isAdmin
            ? HeroiconsOutline.shieldCheck
            : staff.isManager
                ? HeroiconsOutline.shieldExclamation
                : AppIcons.person,
      ),
    );
  }
}
