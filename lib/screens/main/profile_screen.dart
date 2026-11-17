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
          child: _InfoList(
            rows: [
              (label: 'Email', value: account?.email ?? 'Not available'),
              (
                label: 'Role',
                value: isAdmin
                    ? 'Administrator'
                    : isManager
                        ? 'Manager'
                        : 'Staff member',
              ),
              (
                label: 'Account created',
                value: account == null
                    ? 'Not available'
                    : DateTimeUtils.formatDateTime(account.createdAt),
              ),
              if (account?.lastLoginAt != null)
                (
                  label: 'Last login',
                  value: DateTimeUtils.formatDateTime(account!.lastLoginAt!),
                ),
            ],
          ),
        ),
        if (staff != null)
          AdminSection(
            label: 'Staff information',
            child: _InfoList(
              rows: [
                (label: 'Name', value: staff.name),
                (
                  label: 'Position',
                  value: staff.hasManagerAccess ? 'Manager' : 'Staff member',
                ),
                (
                  label: 'Staff since',
                  value: DateTimeUtils.formatDate(staff.createdAt),
                ),
                (label: 'Role', value: _roleName(staff.role)),
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
                    icon: AppIcons.showAll,
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
                  icon: AppIcons.report,
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
                  icon: AppIcons.link,
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
        const ConnectivityIndicator(padding: EdgeInsets.only(bottom: 12)),
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
            style: appDestructiveButtonStyle(context),
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
                ? 'Staff member'
                : 'Account not linked';

    return AppPanel(
      child: Row(
        children: [
          AppIconTile(
            icon: isAdmin ? AppIcons.admin : AppIcons.person,
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
                  icon: linked ? null : AppIcons.link,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Display name of a staff role key ("admin" → "Administrator").
String _roleName(String role) => switch (role) {
      'admin' => 'Administrator',
      'manager' => 'Manager',
      'staff' => 'Staff member',
      _ => role.isEmpty ? 'Not set' : role,
    };

/// A card of label–value rows. Values sit at the trailing edge when every
/// row fits on one line; otherwise (a long email, a narrow screen, large
/// text) every row in the card stacks the value under its label, so the
/// alignment stays uniform and nothing breaks mid-word.
class _InfoList extends StatelessWidget {
  const _InfoList({required this.rows});

  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = _needsStacking(context, constraints.maxWidth);
      return AppGroupedList(
        children: [
          for (final row in rows)
            stacked
                ? AppListRow(
                    title: row.label,
                    subtitle: _breakable(row.value),
                    semanticLabel: '${row.label}, ${row.value}',
                  )
                : AppListRow(title: row.label, detail: row.value),
        ],
      );
    });
  }

  bool _needsStacking(BuildContext context, double width) {
    if (!width.isFinite) return true;
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler.scale(17) > 22) return true;
    final style = DefaultTextStyle.of(context).style.merge(AppTypography.body);
    final direction = Directionality.of(context);
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    // Row padding 16 + 16, an 8 pt gap; the value may take up to 60 %.
    final inner = width - 32;
    for (final row in rows) {
      final value = measure(row.value);
      if (value > inner * 0.6 || measure(row.label) + 8 + value > inner) {
        return true;
      }
    }
    return false;
  }

  /// Lets an email or similar long value wrap after "@" and "." rather than
  /// inside a word.
  static String _breakable(String value) =>
      value.replaceAllMapped(RegExp(r'([@.])'), (m) => '${m[1]}\u200B');
}
