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
import '../admin/admin_page.dart';

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

    final List<Widget> content = user.when(
      loading: () => const [AdminLoading()],
      error: (_, __) => [
        DeliveryMessage(
          icon: AppIcons.error,
          title: 'Couldn’t load your profile',
          action: AppSecondaryButton(
            label: 'Retry',
            icon: AppIcons.retry,
            onPressed: () => ref.invalidate(currentUserProvider),
          ),
        ),
      ],
      data: (account) => [
        _ProfileHeader(
          user: account,
          staff: staff,
          isAdmin: isAdmin,
          isManager: isManager,
        ),
        AdminSection(
          label: 'Account information',
          child: AppGroupedList(
            children: [
              _InfoRow(
                  label: 'Email', value: account?.email ?? 'Not available'),
              _InfoRow(
                label: 'Role',
                value: isAdmin
                    ? 'Administrator'
                    : isManager
                        ? 'Manager'
                        : 'Staff Member',
              ),
              _InfoRow(
                label: 'Account created',
                value: account == null
                    ? 'Not available'
                    : DateTimeUtils.formatDateTime(account.createdAt),
              ),
              if (account?.lastLoginAt != null)
                _InfoRow(
                  label: 'Last login',
                  value: DateTimeUtils.formatDateTime(account!.lastLoginAt!),
                ),
            ],
          ),
        ),
        if (staff != null)
          AdminSection(
            label: 'Staff information',
            child: AppGroupedList(
              children: [
                _InfoRow(label: 'Name', value: staff.name),
                _InfoRow(
                  label: 'Position',
                  value: staff.hasManagerAccess ? 'Manager' : 'Staff Member',
                ),
                _InfoRow(
                  label: 'Staff since',
                  value: DateTimeUtils.formatDate(staff.createdAt),
                ),
                _InfoRow(label: 'Role', value: staff.role),
              ],
            ),
          ),
        if (isManager && !isAdmin)
          AdminSection(
            label: 'Settings',
            child: AppGroupedList(
              children: [
                MergeSemantics(
                  child: AppListRow(
                    icon: HeroiconsOutline.eye,
                    title: 'Show all deliveries',
                    subtitle: 'View all deliveries or only yours',
                    showChevron: false,
                    trailing: Switch(
                      value: showAllDeliveries,
                      onChanged: (value) {
                        ref.read(allDeliveriesProvider.notifier).state = value;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (isAdmin)
          AdminSection(
            label: 'Admin actions',
            child: AppGroupedList(
              separatorIndent: 57,
              children: [
                AppListRow(
                  icon: AppIcons.people,
                  title: 'Staff management',
                  onTap: () => context.go('/profile/staff'),
                ),
                AppListRow(
                  icon: AppIcons.checklist,
                  title: 'Pre-sign-off checklist',
                  onTap: () => context.go('/profile/checklist'),
                ),
                AppListRow(
                  icon: AppIcons.records,
                  title: 'Pre-delivery checklist',
                  onTap: () => context.go('/profile/pre-delivery-checklist'),
                ),
                AppListRow(
                  icon: HeroiconsOutline.documentChartBar,
                  title: 'Season report',
                  subtitle: 'Export end-of-season data',
                  onTap: () => context.go('/profile/season-export'),
                ),
              ],
            ),
          ),
        if (staff == null && !isAdmin)
          AdminSection(
            label: 'Actions',
            child: AppGroupedList(
              separatorIndent: 57,
              children: [
                AppListRow(
                  icon: HeroiconsOutline.link,
                  title: 'Link to staff account',
                  onTap: () => context.go('/staff-link'),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppTokens.sectionGap),
        AdminDestructiveButton(
          label: 'Sign out',
          icon: AppIcons.logout,
          onPressed: () => _showSignOutDialog(context),
        ),
      ],
    );

    return AdminPage(
      title: 'Profile',
      showBack: false,
      children: [
        const ConnectivityIndicator(),
        ...content,
      ],
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: adminDestructiveStyle(context),
            onPressed: () {
              Navigator.pop(context);
              ref.read(authNotifierProvider.notifier).signOut();
            },
            child: const Text('Sign out'),
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
    final colors = AppPalette.of(context);
    final linked = staff != null || isAdmin;
    final role = isAdmin
        ? 'Administrator'
        : isManager
            ? 'Manager'
            : linked
                ? 'Staff Member'
                : 'Account not linked';

    return AppPanel(
      child: Row(
        children: [
          AppIconTile(
            icon: isAdmin ? HeroiconsOutline.shieldCheck : AppIcons.person,
            size: 48,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staff?.name ?? user?.email ?? 'User',
                  style: AppTypography.title2.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 6),
                AppStatusPill(
                  label: role,
                  icon: linked ? null : HeroiconsOutline.link,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label–value row. Side by side when there is room; the value moves under
/// the label on narrow screens or with large text so nothing is truncated.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(17) > 22;
      return stacked
          ? AppListRow(title: label, subtitle: value)
          : AppListRow(title: label, detail: value);
    });
  }
}
