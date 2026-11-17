import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/staff.dart';
import '../../models/user.dart';
import '../../providers/auth_providers.dart';
import '../../providers/deliveries_providers.dart';
import '../../services/date_utils.dart';
import '../../widgets/connectivity_indicator.dart';
import '../../widgets/delivery_day_list.dart';
import '../../widgets/design/design.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(currentUserProvider);
      ref.invalidate(currentStaffProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final staff = ref.watch(currentStaffProvider).valueOrNull;
    final isAdmin = ref.watch(isAdminProvider);
    final isManager = ref.watch(isManagerProvider);
    final showAllDeliveries = ref.watch(allDeliveriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Column(
        children: [
          const ConnectivityIndicator(),
          Expanded(
            child: user.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: DeliveryMessage(
                  icon: Icons.error_outline,
                  title: 'Couldn’t load your profile',
                  action: TextButton(
                    onPressed: () => ref.invalidate(currentUserProvider),
                    child: const Text('Retry'),
                  ),
                ),
              ),
              data: (account) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.gutter,
                      8,
                      AppTokens.gutter,
                      AppTokens.sectionGap,
                    ),
                    children: [
                      _ProfileHeader(
                        user: account,
                        staff: staff,
                        isAdmin: isAdmin,
                        isManager: isManager,
                      ),
                      _ProfileSection(
                        title: 'Account information',
                        children: [
                          _ProfileRow(
                            icon: Icons.mail_outline_rounded,
                            title: 'Email',
                            detail: account?.email ?? 'Not available',
                          ),
                          _ProfileRow(
                            icon: Icons.badge_outlined,
                            title: 'Role',
                            detail: isAdmin
                                ? 'Administrator'
                                : isManager
                                    ? 'Manager'
                                    : 'Staff Member',
                          ),
                          _ProfileRow(
                            icon: Icons.calendar_today_outlined,
                            title: 'Account Created',
                            detail: account == null
                                ? 'Not available'
                                : DateTimeUtils.formatDateTime(
                                    account.createdAt),
                          ),
                          if (account?.lastLoginAt != null)
                            _ProfileRow(
                              icon: Icons.schedule,
                              title: 'Last Login',
                              detail: DateTimeUtils.formatDateTime(
                                  account!.lastLoginAt!),
                            ),
                        ],
                      ),
                      if (staff != null)
                        _ProfileSection(
                          title: 'Staff information',
                          children: [
                            _ProfileRow(
                              icon: Icons.person_outline,
                              tone: AppTone.green,
                              title: 'Name',
                              detail: staff.name,
                            ),
                            _ProfileRow(
                              icon: Icons.work_outline,
                              tone: AppTone.green,
                              title: 'Position',
                              detail: staff.hasManagerAccess
                                  ? 'Manager'
                                  : 'Staff Member',
                            ),
                            _ProfileRow(
                              icon: Icons.today_outlined,
                              tone: AppTone.green,
                              title: 'Staff Since',
                              detail: DateTimeUtils.formatDate(staff.createdAt),
                            ),
                            _ProfileRow(
                              icon: Icons.badge_outlined,
                              tone: AppTone.green,
                              title: 'Role',
                              detail: staff.role,
                            ),
                          ],
                        ),
                      if (isManager && !isAdmin)
                        _ProfileSection(
                          title: 'Settings',
                          children: [
                            SwitchListTile(
                              secondary: const AppIconTile(
                                icon: Icons.visibility_outlined,
                                tone: AppTone.green,
                              ),
                              title: const Text('Show All Deliveries'),
                              subtitle: const Text(
                                  'View all deliveries or only yours'),
                              value: showAllDeliveries,
                              onChanged: (value) {
                                ref.read(allDeliveriesProvider.notifier).state =
                                    value;
                              },
                            ),
                          ],
                        ),
                      if (isAdmin)
                        _ProfileSection(
                          title: 'Admin actions',
                          children: [
                            _ProfileRow(
                              icon: Icons.people_outline,
                              title: 'Staff Management',
                              onTap: () => context.go('/profile/staff'),
                            ),
                            _ProfileRow(
                              icon: Icons.fact_check_outlined,
                              tone: AppTone.green,
                              title: 'Pre-Signoff Checklist',
                              onTap: () => context.go('/profile/checklist'),
                            ),
                            _ProfileRow(
                              icon: Icons.checklist_rtl,
                              tone: AppTone.green,
                              title: 'Pre-Delivery Checklist',
                              onTap: () =>
                                  context.go('/profile/pre-delivery-checklist'),
                            ),
                            _ProfileRow(
                              icon: Icons.summarize_outlined,
                              tone: AppTone.yellow,
                              title: 'Season Report',
                              detail: 'Export end-of-season data',
                              onTap: () => context.go('/profile/season-export'),
                            ),
                          ],
                        ),
                      _ProfileSection(
                        title: 'Actions',
                        children: [
                          if (staff == null && !isAdmin)
                            _ProfileRow(
                              icon: Icons.link,
                              title: 'Link to Staff Account',
                              onTap: () => context.go('/staff-link'),
                            ),
                          _ProfileRow(
                            icon: Icons.logout_rounded,
                            tone: AppTone.pink,
                            title: 'Sign Out',
                            onTap: () => _showSignOutDialog(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
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

  final AppUser? user;
  final Staff? staff;
  final bool isAdmin;
  final bool isManager;

  @override
  Widget build(BuildContext context) {
    final linked = staff != null || isAdmin;
    final tone = isAdmin
        ? AppTone.pink
        : linked
            ? AppTone.green
            : AppTone.blue;

    return AppPanel(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          AppIconTile(
            icon: isAdmin
                ? Icons.admin_panel_settings_outlined
                : Icons.person_outline_rounded,
            tone: tone,
            size: 58,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staff?.name ?? user?.email ?? 'User',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                AppStatusPill(
                  tone: tone,
                  label: isAdmin
                      ? 'Administrator'
                      : isManager
                          ? 'Manager'
                          : linked
                              ? 'Staff Member'
                              : 'Account not linked',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: AppPalette.of(context).muted)),
          ),
          AppGroupedList(children: children),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    this.detail,
    this.onTap,
    this.tone = AppTone.blue,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onTap;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AppIconTile(icon: icon, tone: tone),
      title: Text(title),
      subtitle: detail != null ? Text(detail!) : null,
      trailing: onTap != null
          ? Icon(Icons.chevron_right_rounded,
              color: AppPalette.of(context).muted)
          : null,
      onTap: onTap,
    );
  }
}
