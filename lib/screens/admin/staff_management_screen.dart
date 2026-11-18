import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/staff_providers.dart';
import '../../providers/calendar_metadata_provider.dart';
import '../../models/staff.dart';
import '../../repositories/staff_repository.dart';
import '../../services/date_utils.dart';
import '../../services/result.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';
import '../../widgets/admin/calendar_management_dialog.dart';
import 'admin_page.dart';

enum _StaffChoice {
  edit,
  addSignIn,
  invite,
  passwordReset,
  signInOff,
  signInOn,
  makeSuperAdmin,
  removeSuperAdmin,
  calendar,
  delete,
}

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
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(staffListProvider);
    ref.invalidate(teamDirectoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final staffListAsync = ref.watch(staffListProvider);
    final superAdmin = ref.watch(isSuperAdminProvider);
    final team = superAdmin ? ref.watch(teamDirectoryProvider) : null;
    final directory = team?.valueOrNull;
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
            onPressed: _refresh,
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
          if (team != null && team.hasError)
            DeliveryMessage(
              icon: AppIcons.error,
              title: 'Sign-in details could not be loaded',
              description: '${team.error}',
              action: AppSecondaryButton(
                label: 'Retry',
                icon: AppIcons.retry,
                onPressed: _refresh,
              ),
            ),
          AppGroupedList(
            separatorIndent: 57,
            children: [
              for (final staff in staffList)
                _StaffRow(
                  key: ValueKey(staff.id),
                  staff: staff,
                  account: directory?.accounts[staff.id],
                  isSelf: directory?.callerStaffId == staff.id,
                  onOptions: () => _showStaffOptions(
                    staff,
                    superAdmin: superAdmin,
                    directory: directory,
                  ),
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
            _refresh();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Refreshing staff list...'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
      ],
      // Only super admins add people; other admins manage calendars here.
      action: superAdmin
          ? AppGlassPrimaryButton(
              label: 'Add staff',
              icon: AppIcons.add,
              onPressed: _showAddStaffDialog,
            )
          : null,
      children: content,
    );
  }

  Future<void> _showStaffOptions(
    Staff staff, {
    required bool superAdmin,
    required TeamDirectory? directory,
  }) async {
    final account = directory?.accounts[staff.id];
    final isSelf = directory?.callerStaffId == staff.id;
    final hasLogin = account?.hasLogin ?? false;
    final actions = <AdminSheetAction<_StaffChoice>>[
      if (superAdmin) ...[
        const AdminSheetAction(
            value: _StaffChoice.edit, label: 'Edit', icon: AppIcons.edit),
        if (directory != null && !hasLogin) ...[
          const AdminSheetAction(
              value: _StaffChoice.addSignIn,
              label: 'Create sign-in',
              icon: AppIcons.addSignIn),
          const AdminSheetAction(
              value: _StaffChoice.invite,
              label: 'Create invitation',
              icon: AppIcons.invitation),
        ],
        if (hasLogin && account?.email != null)
          const AdminSheetAction(
              value: _StaffChoice.passwordReset,
              label: 'Send password reset email',
              icon: AppIcons.passwordReset),
        if (hasLogin && !isSelf && staff.isAdmin)
          account!.superAdmin
              ? const AdminSheetAction(
                  value: _StaffChoice.removeSuperAdmin,
                  label: 'Remove super admin',
                  icon: AppIcons.superAdmin)
              : const AdminSheetAction(
                  value: _StaffChoice.makeSuperAdmin,
                  label: 'Make super admin',
                  icon: AppIcons.superAdmin),
        if (hasLogin && !isSelf && !account!.superAdmin)
          account.signInEnabled
              ? const AdminSheetAction(
                  value: _StaffChoice.signInOff,
                  label: 'Turn off sign-in',
                  icon: AppIcons.signInOff)
              : const AdminSheetAction(
                  value: _StaffChoice.signInOn,
                  label: 'Turn on sign-in',
                  icon: AppIcons.signInOn),
      ],
      const AdminSheetAction(
          value: _StaffChoice.calendar,
          label: 'Manage calendar',
          icon: AppIcons.calendar),
      if (superAdmin &&
          directory != null &&
          !isSelf &&
          !(account?.superAdmin ?? false))
        const AdminSheetAction(
            value: _StaffChoice.delete,
            label: 'Delete',
            icon: AppIcons.delete,
            destructive: true),
    ];
    final choice = await showAdminActionSheet<_StaffChoice>(
      context,
      title: staff.name,
      actions: actions,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _StaffChoice.edit:
        _showEditStaffDialog(staff, isSelf: isSelf, account: account);
      case _StaffChoice.addSignIn:
        _showAddSignInDialog(staff);
      case _StaffChoice.invite:
        _issueInvite(staff);
      case _StaffChoice.passwordReset:
        _confirmPasswordReset(staff, account!.email!);
      case _StaffChoice.signInOff:
        _confirmSignIn(staff, enabled: false);
      case _StaffChoice.signInOn:
        _confirmSignIn(staff, enabled: true);
      case _StaffChoice.makeSuperAdmin:
        _confirmSuperAdmin(staff, superAdmin: true);
      case _StaffChoice.removeSuperAdmin:
        _confirmSuperAdmin(staff, superAdmin: false);
      case _StaffChoice.calendar:
        _showCalendarManagementDialog(staff);
      case _StaffChoice.delete:
        _showDeleteStaffDialog(staff, hasLogin: hasLogin);
    }
  }

  /// Asks before a team change, then runs it and reports the outcome.
  Future<void> _confirmTeamChange({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
    required Future<Result<void>> Function() change,
    required String done,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive ? appDestructiveButtonStyle(context) : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await change();
    if (!mounted) return;
    if (result.isFailure) {
      _showError(result.errorOrNull ?? 'That change could not be made.');
      return;
    }
    _refresh();
    _showMessage(done);
  }

  void _confirmPasswordReset(Staff staff, String email) {
    _confirmTeamChange(
      title: 'Reset password',
      message: 'Send ${staff.name} an email at $email with a link to choose '
          'a new password? Their current password keeps working until they '
          'change it.',
      confirmLabel: 'Send email',
      change: () => ref.read(staffRepositoryProvider).sendPasswordReset(email),
      done: 'Password reset email sent to $email',
    );
  }

  void _confirmSignIn(Staff staff, {required bool enabled}) {
    _confirmTeamChange(
      title: enabled ? 'Turn on sign-in' : 'Turn off sign-in',
      message: enabled
          ? '${staff.name} will be able to sign in again.'
          : '${staff.name} will be signed out on their devices within an '
              'hour and won\'t be able to sign in until you turn it back on. '
              'Their records are kept.',
      confirmLabel: enabled ? 'Turn on' : 'Turn off',
      destructive: !enabled,
      change: () =>
          ref.read(staffRepositoryProvider).setTeamSignIn(staff.id, enabled),
      done: enabled
          ? '${staff.name} can sign in again'
          : 'Sign-in turned off for ${staff.name}',
    );
  }

  void _confirmSuperAdmin(Staff staff, {required bool superAdmin}) {
    _confirmTeamChange(
      title: superAdmin ? 'Make super admin' : 'Remove super admin',
      message: superAdmin
          ? '${staff.name} will be able to add and remove people, change '
              'access levels, manage sign-ins and make other super admins.'
          : '${staff.name} will stay an admin but will no longer manage the '
              'team.',
      confirmLabel: superAdmin ? 'Make super admin' : 'Remove',
      destructive: !superAdmin,
      change: () => ref
          .read(staffRepositoryProvider)
          .setTeamSuperAdmin(staff.id, superAdmin),
      done: superAdmin
          ? '${staff.name} is now a super admin'
          : '${staff.name} is no longer a super admin',
    );
  }

  void _showAddSignInDialog(Staff staff) {
    final emailController = TextEditingController();
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text('Create sign-in for ${staff.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'They will get an email with a link to choose their password.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(AppIcons.email, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              Navigator.of(dialogContext).pop();
              _createSignIn(email: email, staffId: staff.id, name: staff.name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  /// Creates the sign-in, then emails the person a set-password link.
  Future<void> _createSignIn({
    required String email,
    String? staffId,
    required String name,
    String? role,
  }) async {
    final repository = ref.read(staffRepositoryProvider);
    final created = await repository.createTeamAccount(
      email: email,
      staffId: staffId,
      name: staffId == null ? name : null,
      role: staffId == null ? role : null,
    );
    if (!mounted) return;
    if (created.isFailure) {
      _showError(created.errorOrNull ?? 'Could not create the sign-in.');
      return;
    }
    _refresh();
    final sent = await repository.sendPasswordReset(email.toLowerCase());
    if (!mounted) return;
    _showMessage(sent.isSuccess
        ? '$name can sign in once they choose a password from the email sent '
            'to ${email.toLowerCase()}'
        : 'Sign-in created for $name, but the email could not be sent. Use '
            'Send password reset email to try again.');
  }

  void _showAddStaffDialog() {
    _showStaffDialog(null);
  }

  void _showEditStaffDialog(
    Staff staff, {
    required bool isSelf,
    TeamAccount? account,
  }) {
    // Debug: Check if staff ID is empty
    if (staff.id.isEmpty) {
      _showError(
          'Cannot edit this staff member: Invalid data. Please contact support.');
      if (kDebugMode) {
        debugPrint('Staff record is missing its document ID');
      }
      return;
    }

    // A super admin's role is fixed until super admin is removed, and
    // nobody changes their own role.
    final roleLocked = isSelf || (account?.superAdmin ?? false);
    _showStaffDialog(
      staff,
      roleNote: !roleLocked
          ? null
          : isSelf
              ? 'You can\'t change your own role.'
              : 'Remove super admin before changing this role.',
    );
  }

  void _showStaffDialog(Staff? staff, {String? roleNote}) {
    final nameController = TextEditingController(text: staff?.name ?? '');
    final emailController = TextEditingController();
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
                  onChanged: roleNote != null
                      ? null
                      : (value) {
                          setState(() {
                            selectedRole = value ?? 'staff';
                          });
                        },
                ),
                if (roleNote != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    roleNote,
                    style: AppTypography.subheadline
                        .copyWith(color: AppPalette.of(context).muted),
                  ),
                ],
                if (staff == null) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Sign-in email (optional)',
                      helperText:
                          'They get an email to choose a password. Leave '
                          'blank to share an invitation code instead.',
                      helperMaxLines: 3,
                      prefixIcon: Icon(AppIcons.email, size: 20),
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
                onPressed: () => _saveStaff(staff, nameController.text,
                    selectedRole, emailController.text.trim()),
                child: Text(staff == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveStaff(
      Staff? existingStaff, String name, String role, String email) async {
    if (name.trim().isEmpty) {
      _showError('Please enter a name');
      return;
    }

    Navigator.of(context, rootNavigator: false).pop();

    if (existingStaff == null && email.isNotEmpty) {
      await _createSignIn(email: email, name: name.trim(), role: role);
    } else if (existingStaff == null) {
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

  void _showDeleteStaffDialog(Staff staff, {required bool hasLogin}) {
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
              if (hasLogin)
                Text(
                  'Their sign-in will be deleted too. Past visit records keep their name.',
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
                await _deleteStaff(staff, hasLogin: hasLogin);
              },
              style: appDestructiveButtonStyle(context),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteStaff(Staff staff, {required bool hasLogin}) async {
    try {
      // People with a sign-in are removed on the server so their access link
      // and sign-in go too; a record without one is deleted directly.
      final result = hasLogin
          ? await ref.read(staffRepositoryProvider).deleteTeamMember(staff.id)
          : await ref.read(deliveriesRepositoryProvider).deleteStaff(staff.id);

      result.when(
        success: (_) {
          _refresh();
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

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
  const _StaffRow({
    super.key,
    required this.staff,
    required this.onOptions,
    this.account,
    this.isSelf = false,
  });

  final Staff staff;
  final VoidCallback onOptions;

  /// Sign-in details, present only for super admins.
  final TeamAccount? account;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final account = this.account;
    final isLinked = account?.hasLogin ?? staff.uid != null;
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
                Text(isSelf ? '${staff.name} (you)' : staff.name,
                    style: AppTypography.headline.copyWith(color: colors.ink)),
                if (account?.email != null) ...[
                  const SizedBox(height: 2),
                  Text(account!.email!,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted)),
                ],
                if (account?.lastSignInAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                      'Last signed in '
                      '${DateTimeUtils.formatDate(account!.lastSignInAt!)}',
                      style:
                          AppTypography.footnote.copyWith(color: colors.muted)),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (account?.superAdmin ?? false)
                      const AppStatusPill(
                          label: 'Super admin', icon: AppIcons.superAdmin),
                    if (account != null &&
                        account.hasLogin &&
                        !account.signInEnabled)
                      const AppStatusPill(
                          label: 'Sign-in off',
                          icon: AppIcons.signInOff,
                          tone: AppTone.warning),
                    if (staff.isAdmin)
                      const AppStatusPill(label: 'Admin')
                    else if (staff.isManager)
                      const AppStatusPill(label: 'Manager'),
                    AppStatusPill(
                      label: isLinked
                          ? (account == null
                              ? 'Linked to user account'
                              : 'Has sign-in')
                          : (account == null ? 'Not linked' : 'No sign-in'),
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
