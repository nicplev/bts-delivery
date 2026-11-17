import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/staff_providers.dart';
import '../../providers/calendar_metadata_provider.dart';
import '../../models/staff.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';
import '../../widgets/admin/calendar_management_dialog.dart';
import 'admin_page.dart';

enum _StaffChoice { edit, invite, calendar, delete }

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Set up auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        ref.invalidate(staffListProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staffListAsync = ref.watch(staffListProvider);
    final count = staffListAsync.valueOrNull?.length;

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
              description: 'Use Add staff to add your first staff member.',
            ),
          ];
        }
        return [
          AppGroupedList(
            separatorIndent: 57,
            children: [
              for (final staff in staffList)
                _StaffRow(
                  key: ValueKey(staff.id),
                  staff: staff,
                  onOptions: () => _showStaffOptions(staff),
                ),
            ],
          ),
        ];
      },
    );

    return AdminPage(
      backLabel: 'Back to profile',
      title: 'Staff management',
      subtitle: count == null
          ? null
          : '$count staff ${count == 1 ? 'member' : 'members'}',
      navActions: [
        AppGlassIconButton(
          icon: AppIcons.retry,
          semanticLabel: 'Refresh',
          onPressed: () {
            ref.invalidate(staffListProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Refreshing staff list...'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
      ],
      action: AppGlassPrimaryButton(
        label: 'Add staff',
        icon: AppIcons.add,
        onPressed: _showAddStaffDialog,
      ),
      children: content,
    );
  }

  Future<void> _showStaffOptions(Staff staff) async {
    final choice = await showAdminActionSheet<_StaffChoice>(
      context,
      title: staff.name,
      actions: const [
        AdminSheetAction(
            value: _StaffChoice.edit, label: 'Edit', icon: AppIcons.edit),
        AdminSheetAction(
            value: _StaffChoice.invite,
            label: 'Create invitation',
            icon: AppIcons.invitation),
        AdminSheetAction(
            value: _StaffChoice.calendar,
            label: 'Manage calendar',
            icon: AppIcons.calendar),
        AdminSheetAction(
            value: _StaffChoice.delete,
            label: 'Delete',
            icon: AppIcons.delete,
            destructive: true),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _StaffChoice.edit:
        _showEditStaffDialog(staff);
      case _StaffChoice.invite:
        _issueInvite(staff);
      case _StaffChoice.calendar:
        _showCalendarManagementDialog(staff);
      case _StaffChoice.delete:
        _showDeleteStaffDialog(staff);
    }
  }

  void _showAddStaffDialog() {
    _showStaffDialog(null);
  }

  void _showEditStaffDialog(Staff staff) {
    // Debug: Check if staff ID is empty
    if (staff.id.isEmpty) {
      _showError(
          'Cannot edit this staff member: Invalid data. Please contact support.');
      if (kDebugMode) {
        debugPrint('Staff record is missing its document ID');
      }
      return;
    }

    _showStaffDialog(staff);
  }

  void _showStaffDialog(Staff? staff) {
    final nameController = TextEditingController(text: staff?.name ?? '');
    String selectedRole = staff?.role ?? 'staff';

    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            scrollable: true,
            title:
                Text(staff == null ? 'Add staff member' : 'Edit staff member'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(AppIcons.person, size: 20),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  isExpanded: true,
                  icon: const Icon(AppIcons.chevronDown, size: 20),
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(AppIcons.role, size: 20),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'staff', child: Text('Staff')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedRole = value ?? 'staff';
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    _saveStaff(staff, nameController.text, selectedRole),
                child: Text(staff == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveStaff(
      Staff? existingStaff, String name, String role) async {
    if (name.trim().isEmpty) {
      _showError('Please enter a name');
      return;
    }

    Navigator.of(context, rootNavigator: false).pop();

    if (existingStaff == null) {
      final newStaff = Staff(
        id: '',
        name: name.trim(),
        role: role,
        createdAt: DateTime.now(),
      );
      final created = await _createStaff(newStaff);
      if (created != null && mounted) {
        ref.invalidate(staffListProvider);
        await _issueInvite(created);
      }
    } else {
      // Update existing staff
      final updatedStaff = existingStaff.copyWith(
        name: name.trim(),
        role: role,
      );

      final success = await _updateStaff(updatedStaff);
      if (success) {
        ref.invalidate(staffListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Staff member updated successfully'),
            ),
          );
        }
      }
    }
  }

  Future<Staff?> _createStaff(Staff staff) async {
    final result = await ref.read(staffRepositoryProvider).createStaff(staff);
    if (result.isFailure && mounted) {
      _showError(result.errorOrNull ?? 'Could not add staff.');
    }
    return result.dataOrNull;
  }

  Future<bool> _updateStaff(Staff staff) async {
    try {
      final deliveriesRepository = ref.read(deliveriesRepositoryProvider);
      final result = await deliveriesRepository.updateStaff(staff);

      return result.when(
        success: (_) => true,
        failure: (message, exception) {
          _showError(message);
          return false;
        },
      );
    } catch (e) {
      _showError('Unexpected error: $e');
      return false;
    }
  }

  Future<void> _issueInvite(Staff staff) async {
    final result =
        await ref.read(staffRepositoryProvider).issueInvite(staff.id);
    if (!mounted) return;
    final code = result.dataOrNull;
    if (code == null) {
      _showError(result.errorOrNull ?? 'Could not create an invitation.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        final colors = AppPalette.of(context);
        return AlertDialog(
          scrollable: true,
          title: Text('Invitation for ${staff.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Share this code privately with the staff member. It expires in 24 hours and can be used once. Creating a new code replaces this one.',
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceQuiet,
                  borderRadius: BorderRadius.circular(AppTokens.controlRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    code,
                    style: AppTypography.headline
                        .copyWith(color: colors.ink, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copy code'),
            ),
          ],
        );
      },
    );
  }

  void _showCalendarManagementDialog(Staff staff) {
    // Debug: Check if staff ID is empty
    if (staff.id.isEmpty) {
      _showError(
          'Cannot manage calendar for this staff member: Invalid data. Please contact support.');
      if (kDebugMode) {
        debugPrint('Staff record is missing its document ID');
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) => CalendarManagementDialog(staff: staff),
    ).then((_) {
      // Refresh the staff list when dialog closes to update calendar status
      ref.invalidate(staffListProvider);
    });
  }

  void _showDeleteStaffDialog(Staff staff) {
    // Debug: Check if staff ID is empty
    if (staff.id.isEmpty) {
      _showError(
          'Cannot delete this staff member: Invalid data. Please contact support.');
      if (kDebugMode) {
        debugPrint('Staff record is missing its document ID');
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        final colors = AppPalette.of(context);
        return AlertDialog(
          scrollable: true,
          title: const Text('Delete staff member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to delete "${staff.name}"?'),
              const SizedBox(height: 8),
              if (staff.uid != null)
                Text(
                  'Warning: This staff member is linked to a user account. Deleting will unlink their account.',
                  style:
                      AppTypography.subheadline.copyWith(color: colors.muted),
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                // Close dialog first
                Navigator.of(context).pop();
                // Then delete
                await _deleteStaff(staff);
              },
              style: appDestructiveButtonStyle(context),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteStaff(Staff staff) async {
    try {
      final deliveriesRepository = ref.read(deliveriesRepositoryProvider);
      final result = await deliveriesRepository.deleteStaff(staff.id);

      result.when(
        success: (_) {
          ref.invalidate(staffListProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Staff member deleted successfully'),
              ),
            );
          }
        },
        failure: (message, exception) {
          if (mounted) {
            _showError(message);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        _showError('Unexpected error: $e');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    }
  }
}

/// One staff member: role icon tile, name, neutral status pills (role, account
/// link, calendar subscription) and the options control.
class _StaffRow extends StatelessWidget {
  const _StaffRow({super.key, required this.staff, required this.onOptions});

  final Staff staff;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final isLinked = staff.uid != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIconTile(
              size: 29,
              icon: staff.isAdmin
                  ? AppIcons.admin
                  : staff.isManager
                      ? AppIcons.manager
                      : AppIcons.person,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.name,
                    style: AppTypography.headline.copyWith(color: colors.ink)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (staff.isAdmin)
                      const AppStatusPill(label: 'Admin')
                    else if (staff.isManager)
                      const AppStatusPill(label: 'Manager'),
                    AppStatusPill(
                      label: isLinked ? 'Linked to user account' : 'Not linked',
                      icon: isLinked ? AppIcons.check : AppIcons.link,
                    ),
                    Consumer(
                      builder: (context, ref, child) {
                        final calendar =
                            ref.watch(calendarMetadataProvider(staff.id));
                        return calendar.when(
                          skipLoadingOnRefresh: false,
                          data: (metadata) {
                            if (metadata == null) {
                              return const SizedBox.shrink();
                            }
                            return AppStatusPill(
                              label: metadata.isActive
                                  ? 'Calendar: Active'
                                  : 'Calendar: Not subscribed',
                              icon: AppIcons.calendar,
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const AppStatusPill(
                            label: 'Calendar status unavailable',
                            icon: AppIcons.infoOutline,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          AdminOptionsButton(
            semanticLabel: 'Staff member actions',
            onPressed: onOptions,
          ),
        ],
      ),
    );
  }
}
