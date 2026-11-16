import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/calendar_metadata_provider.dart';
import '../../models/staff.dart';
import '../../app/theme/brand_colors.dart';
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
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No staff members found'),
                  SizedBox(height: 8),
                  Text(
                    'Tap the + button to add your first staff member.',
                    style: TextStyle(color: Colors.grey),
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
            padding: const EdgeInsets.all(16),
            itemCount: staffList.length,
            itemBuilder: (context, index) {
              final staff = staffList[index];
              final isLinked = staff.uid != null;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: staff.isAdmin
                        ? BrandColors.kakaPink
                        : staff.isManager
                            ? BrandColors.kakaBlue
                            : Theme.of(context).primaryColor,
                    child: Icon(
                      staff.isAdmin
                          ? Icons.admin_panel_settings
                          : staff.isManager
                              ? Icons.shield
                              : Icons.person,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(staff.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (staff.isAdmin)
                        const Text('Admin',
                            style: TextStyle(color: BrandColors.kakaPink))
                      else if (staff.isManager)
                        const Text('Manager',
                            style: TextStyle(color: BrandColors.kakaBlue)),
                      if (isLinked)
                        const Text('Linked to user account',
                            style: TextStyle(color: Colors.green))
                      else
                        const Text('Not linked',
                            style: TextStyle(color: Colors.grey)),
                      // Calendar status indicator
                      Consumer(
                        builder: (context, ref, child) {
                          final calendarMetadataAsync = ref.watch(calendarMetadataProvider(staff.id));
                          return calendarMetadataAsync.when(
                            data: (metadata) {
                              final hasCalendar = staff.hasCalendarToken;
                              final isActive = metadata?.isActive ?? false;

                              if (hasCalendar && isActive) {
                                return Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      size: 14,
                                      color: Colors.deepPurple[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Calendar: Active',
                                      style: TextStyle(
                                        color: Colors.deepPurple[700],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                );
                              } else if (hasCalendar) {
                                return Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Calendar: Not subscribed',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return const SizedBox.shrink();
                              }
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
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
                        case 'regenerate_pin':
                          _showRegeneratePinDialog(staff);
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
                      PopupMenuItem(
                        value: 'edit',
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'regenerate_pin',
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.pin_outlined,
                              size: 20,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              staff.linkPin == null ? 'Generate PIN' : 'Regenerate PIN',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'manage_calendar',
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 20,
                              color: Colors.deepPurple.shade700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Manage Calendar',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
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
      _showError('Cannot edit this staff member: Invalid data. Please contact support.');
      if (kDebugMode) {
        debugPrint('ERROR: Staff has empty ID - ${staff.toJson()}');
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

  String _generatePin() {
    // Generate a random 4-digit PIN
    final random = DateTime.now().millisecondsSinceEpoch % 10000;
    return random.toString().padLeft(4, '0');
  }

  Future<void> _saveStaff(
      Staff? existingStaff, String name, String role) async {
    if (name.trim().isEmpty) {
      _showError('Please enter a name');
      return;
    }

    Navigator.of(context, rootNavigator: false).pop();

    if (existingStaff == null) {
      // Generate a unique 4-digit PIN for account linking
      final linkPin = _generatePin();

      // Create new staff
      final newStaff = Staff(
        id: '', // Will be set by Firestore
        name: name.trim(),
        role: role,
        linkPin: linkPin,
        createdAt: DateTime.now(),
      );

      final success = await _createStaff(newStaff);
      if (success) {
        ref.invalidate(staffListProvider);
        if (mounted) {
          // Show PIN to admin/manager
          _showPinDialog(name.trim(), linkPin);
        }
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
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  Future<bool> _createStaff(Staff staff) async {
    try {
      final deliveriesRepository = ref.read(deliveriesRepositoryProvider);
      final result = await deliveriesRepository.createStaff(staff);

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

  void _showPinDialog(String staffName, String pin) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[600], size: 28),
            const SizedBox(width: 12),
            const Text('Staff Member Added'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$staffName has been added successfully.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!, width: 2),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Account Linking PIN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[300]!, width: 1),
                    ),
                    child: Text(
                      pin,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Share this PIN with $staffName',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[800], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'They will need this PIN to link their account when they first sign in.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  void _showRegeneratePinDialog(Staff staff) {
    // Debug: Check if staff ID is empty
    if (staff.id.isEmpty) {
      _showError('Cannot regenerate PIN for this staff member: Invalid data. Please contact support.');
      if (kDebugMode) {
        debugPrint('ERROR: Staff has empty ID - ${staff.toJson()}');
      }
      return;
    }

    final actionText = staff.linkPin == null ? 'generate' : 'regenerate';
    final titleText = staff.linkPin == null ? 'Generate PIN' : 'Regenerate PIN';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titleText),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to $actionText a PIN for "${staff.name}"?'),
            const SizedBox(height: 12),
            if (staff.linkPin != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_outlined, color: Colors.orange[800], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will replace the existing PIN. The old PIN will no longer work.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[800], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A new 4-digit PIN will be generated for account linking.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
              // Then regenerate PIN
              await _regeneratePin(staff);
            },
            child: Text(staff.linkPin == null ? 'Generate' : 'Regenerate'),
          ),
        ],
      ),
    );
  }

  Future<void> _regeneratePin(Staff staff) async {
    // Generate a new PIN
    final newPin = _generatePin();

    // Update staff with new PIN
    final updatedStaff = staff.copyWith(linkPin: newPin);

    final success = await _updateStaff(updatedStaff);
    if (success) {
      ref.invalidate(staffListProvider);
      if (mounted) {
        // Show the new PIN to admin
        _showPinDialog(staff.name, newPin);
      }
    }
  }

  void _showCalendarManagementDialog(Staff staff) {
    // Debug: Check if staff ID is empty
    if (staff.id.isEmpty) {
      _showError('Cannot manage calendar for this staff member: Invalid data. Please contact support.');
      if (kDebugMode) {
        debugPrint('ERROR: Staff has empty ID - ${staff.toJson()}');
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
      _showError('Cannot delete this staff member: Invalid data. Please contact support.');
      if (kDebugMode) {
        debugPrint('ERROR: Staff has empty ID - ${staff.toJson()}');
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Staff Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${staff.name}"?'),
            const SizedBox(height: 8),
            if (staff.uid != null)
              const Text(
                'Warning: This staff member is linked to a user account. Deleting will unlink their account.',
                style: TextStyle(color: BrandColors.kakaBlue, fontSize: 12),
              ),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontSize: 12),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
                backgroundColor: Colors.green,
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
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
