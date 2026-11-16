import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_providers.dart';
import '../../providers/deliveries_providers.dart';
import '../../models/staff.dart';
import '../../app/theme/brand_colors.dart';

class StaffLinkScreen extends ConsumerWidget {
  const StaffLinkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffListAsync = ref.watch(staffListProvider);
    final authNotifier = ref.read(authNotifierProvider.notifier);
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = ref.watch(isAdminProvider);

    // If user is admin, redirect them to schools instead of showing staff link
    if (isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('/schools');
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link to Staff Profile'),
        actions: [
          TextButton(
            onPressed: () => authNotifier.signOut(),
            child: const Text('Sign Out'),
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No staff members found'),
                  const SizedBox(height: 8),
                  const Text(
                    'Please contact your administrator to add staff profiles.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Add bypass option for admin users or when there are no staff
                  FilledButton.icon(
                    onPressed: () => _bypassStaffLink(context),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Continue to App'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Admin users can skip staff linking',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.link, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          'Select Your Profile',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose your name from the list below to link your account with your staff profile.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: staffList.length,
                  itemBuilder: (context, index) {
                    final staff = staffList[index];
                    final isLinked = staff.uid != null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: staff.hasManagerAccess
                              ? BrandColors.kakaBlue
                              : Theme.of(context).primaryColor,
                          child: Icon(
                            staff.hasManagerAccess
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(staff.name),
                        subtitle: staff.hasManagerAccess
                            ? const Text('Manager',
                                style: TextStyle(color: BrandColors.kakaBlue))
                            : null,
                        trailing: isLinked
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : const Icon(Icons.arrow_forward_ios),
                        onTap: isLinked
                            ? null
                            : authState.isLoading
                                ? null
                                : () => _linkToStaff(context, ref, staff),
                        enabled: !isLinked && !authState.isLoading,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _linkToStaff(
      BuildContext context, WidgetRef ref, Staff staff) async {
    // Show PIN verification dialog
    final pinController = TextEditingController();

    final pinVerified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            const Text('Verify Your Identity'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Link account to ${staff.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Enter the 4-digit PIN provided by your administrator:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 16,
              ),
              decoration: InputDecoration(
                hintText: '- - - -',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This PIN was given to you when your account was created.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final enteredPin = pinController.text.trim();

              // Validate PIN
              if (enteredPin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter your PIN'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (enteredPin.length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN must be 4 digits'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Check if PIN matches
              if (staff.linkPin == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This staff profile does not have a PIN set. Please contact your administrator to set up account linking.'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 5),
                  ),
                );
                return;
              }

              if (enteredPin != staff.linkPin) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect PIN. Please try again or contact your administrator.'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 4),
                  ),
                );
                return;
              }

              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (pinVerified != true) return;

    // PIN verified, proceed with linking
    final authNotifier = ref.read(authNotifierProvider.notifier);
    final success = await authNotifier.linkToStaff(staff.id);

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully linked to ${staff.name}'),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/home');
    }
  }

  void _bypassStaffLink(BuildContext context) {
    context.go('/schools');
  }
}
