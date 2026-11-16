import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_providers.dart';
import '../../providers/deliveries_providers.dart';
import '../../services/date_utils.dart';
import '../../widgets/connectivity_indicator.dart';
import '../../app/theme/brand_colors.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final currentStaffAsync = ref.watch(currentStaffProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final isManager = ref.watch(isManagerProvider);
    final showAllDeliveries = ref.watch(allDeliveriesProvider);

    // Refresh user data when profile page is accessed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(currentUserProvider);
      ref.invalidate(currentStaffProvider);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: Column(
        children: [
          const ConnectivityIndicator(),
          Expanded(
            child: currentUserAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error loading profile: $error'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.invalidate(currentUserProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (user) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Header
                    _ProfileHeader(
                      user: user,
                      staff: currentStaffAsync.value,
                      isAdmin: isAdmin,
                      isManager: isManager,
                    ),

                    const SizedBox(height: 24),

                    // Account Information
                    _ProfileSection(
                      title: 'Account Information',
                      children: [
                        _InfoTile(
                          icon: Icons.email,
                          label: 'Email',
                          value: user?.email ?? 'Not available',
                        ),
                        _InfoTile(
                          icon: Icons.security,
                          label: 'Role',
                          value: isAdmin
                              ? 'Administrator'
                              : isManager
                                  ? 'Manager'
                                  : 'Staff Member',
                        ),
                        _InfoTile(
                          icon: Icons.calendar_today,
                          label: 'Account Created',
                          value: user?.createdAt != null
                              ? DateTimeUtils.formatDateTime(user!.createdAt)
                              : 'Not available',
                        ),
                        if (user?.lastLoginAt != null)
                          _InfoTile(
                            icon: Icons.access_time,
                            label: 'Last Login',
                            value: DateTimeUtils.formatDateTime(
                                user!.lastLoginAt!),
                          ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Staff Information (if linked)
                    if (currentStaffAsync.value != null) ...[
                      _ProfileSection(
                        title: 'Staff Information',
                        children: [
                          _InfoTile(
                            icon: Icons.person,
                            label: 'Name',
                            value: currentStaffAsync.value!.name,
                          ),
                          _InfoTile(
                            icon: Icons.badge,
                            label: 'Position',
                            value: currentStaffAsync.value!.hasManagerAccess
                                ? 'Manager'
                                : 'Staff Member',
                          ),
                          _InfoTile(
                            icon: Icons.calendar_today,
                            label: 'Staff Since',
                            value: DateTimeUtils.formatDate(
                                currentStaffAsync.value!.createdAt),
                          ),
                          _InfoTile(
                            icon: Icons.work,
                            label: 'Role',
                            value: currentStaffAsync.value!.role,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Settings (for managers)
                    if (isManager && !isAdmin) ...[
                      _ProfileSection(
                        title: 'Settings',
                        children: [
                          SwitchListTile(
                            secondary: const Icon(Icons.visibility),
                            title: const Text('Show All Deliveries'),
                            subtitle:
                                const Text('View all deliveries or only yours'),
                            value: showAllDeliveries,
                            onChanged: (value) {
                              ref.read(allDeliveriesProvider.notifier).state =
                                  value;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Admin Actions
                    if (isAdmin) ...[
                      _ProfileSection(
                        title: 'Admin Actions',
                        children: [
                          ListTile(
                            leading: const Icon(Icons.people),
                            title: const Text('Staff Management'),
                            subtitle: const Text('Manage staff members'),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () => context.go('/profile/staff'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.checklist),
                            title: const Text('Pre-Signoff Checklist'),
                            subtitle: const Text('Manage pre-signoff checklist items'),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () => context.go('/profile/checklist'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.checklist_rtl),
                            title: const Text('Pre-Delivery Checklist'),
                            subtitle: const Text('Manage van loading checklist'),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () => context.go('/profile/pre-delivery-checklist'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.summarize),
                            title: const Text('Season Report'),
                            subtitle: const Text('Export end-of-season data'),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () => context.go('/profile/season-export'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Actions Section
                    _ProfileSection(
                      title: 'Actions',
                      children: [
                        if (currentStaffAsync.value == null && !isAdmin)
                          ListTile(
                            leading: const Icon(Icons.link),
                            title: const Text('Link to Staff Account'),
                            subtitle: const Text(
                                'Connect your account to a staff member'),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () => context.go('/staff-link'),
                          ),
                        ListTile(
                          leading: const Icon(Icons.logout, color: Colors.red),
                          title: const Text('Sign Out',
                              style: TextStyle(color: Colors.red)),
                          onTap: () => _showSignOutDialog(context, ref),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authNotifierProvider.notifier).signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.staff,
    required this.isAdmin,
    required this.isManager,
  });

  final dynamic user;
  final dynamic staff;
  final bool isAdmin;
  final bool isManager;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Theme.of(context).primaryColor,
              child: Icon(
                isAdmin
                    ? Icons.admin_panel_settings
                    : isManager
                        ? Icons.supervisor_account
                        : Icons.person,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    staff?.name ?? user?.email ?? 'User',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAdmin
                        ? 'Administrator'
                        : isManager
                            ? 'Manager'
                            : staff != null
                                ? 'Staff Member'
                                : 'Account not linked',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: staff != null || isAdmin
                              ? BrandColors.kakaGreen
                              : BrandColors.kakaBlue,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (staff == null && !isAdmin) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Link your account to access staff features',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(label),
      subtitle: Text(value),
      dense: true,
    );
  }
}
