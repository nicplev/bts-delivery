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
import '../../widgets/design/design.dart';
import '../../widgets/admin/calendar_management_dialog.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          IconButton(
            onPressed: () {
              ref.invalidate(staffListProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing staff list...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: () => _showAddStaffDialog(),
            icon: const Icon(Icons.add),
            tooltip: 'Add Staff Member',
          ),
        ],
      ),
      body: staffListAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error,
                  size: 48, color: Theme.of(context).colorScheme.error),
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
                      size: 48, color: AppPalette.of(context).muted),
                  const SizedBox(height: 16),
                  const Text('No staff members found'),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the + button to add your first staff member.',
                    style: TextStyle(color: AppPalette.of(context).muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Debug: Log staff IDs
          if (kDebugMode) {
            debugPrint('=== Staff List Debug ===');
            for (var s in staffList) {
              debugPrint('Staff: ${s.name}, ID: "${s.id}", UID: ${s.uid}');
            }
            debugPrint('=======================');
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(AppTokens.gutter, 10, AppTokens.gutter,
                MediaQuery.paddingOf(context).bottom + AppTokens.sectionGap),
            itemCount: staffList.length,
            itemBuilder: (context, index) {
              final staff = staffList[index];
              final isLinked = staff.uid != null;

              return AppPanel(
                key: ValueKey(staff.id),
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: AppIconTile(
                    icon: staff.isAdmin
                        ? Icons.admin_panel_settings_outlined
                        : staff.isManager
                            ? Icons.shield_outlined
                            : Icons.person_outline,
                    tone: staff.isAdmin
                        ? AppTone.pink
                        : staff.isManager
                            ? AppTone.blue
                            : AppTone.green,
                  ),
                  title: Text(staff.name),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (staff.isAdmin)
                          const AppStatusPill(
                              label: 'Admin', tone: AppTone.pink)
                        else if (staff.isManager)
                          const AppStatusPill(
                              label: 'Manager', tone: AppTone.blue),
                        AppStatusPill(
                          label: isLinked
                              ? 'Linked to user account'
                              : 'Not linked',
                          tone: isLinked ? AppTone.green : AppTone.neutral,
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
                                  icon: Icons.calendar_today_outlined,
                                  tone: metadata.isActive
                                      ? AppTone.blue
                                      : AppTone.neutral,
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const AppStatusPill(
                                label: 'Calendar status unavailable',
                                icon: Icons.info_outline,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Staff member actions',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                    offset: const Offset(0, 8),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showEditStaffDialog(staff);
                          break;
                        case 'issue_invite':
                          _issueInvite(staff);
                          break;
                        case 'manage_calendar':
                          _showCalendarManagementDialog(staff);
                          break;
                        case 'delete':
                          _showDeleteStaffDialog(staff);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'issue_invite',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.vpn_key_outlined),
                          title: Text('Create invitation'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'manage_calendar',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.calendar_month_outlined),
                          title: Text('Manage Calendar'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error),
                          title: Text('Delete',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
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
                Text(staff == null ? 'Add Staff Member' : 'Edit Staff Member'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.badge),
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
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Invitation for ${staff.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this code privately with the staff member. It expires in 24 hours and can be used once. Creating a new code replaces this one.',
            ),
            const SizedBox(height: 12),
            SelectableText(code),
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
      ),
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
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete Staff Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${staff.name}"?'),
            const SizedBox(height: 8),
            if (staff.uid != null)
              Text(
                'Warning: This staff member is linked to a user account. Deleting will unlink their account.',
                style: TextStyle(
                    color: AppTone.blue.inkFor(context), fontSize: 12),
              ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 12),
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
