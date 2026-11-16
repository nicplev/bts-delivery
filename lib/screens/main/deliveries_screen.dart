import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../providers/auth_providers.dart';
import '../../providers/deliveries_providers.dart';
import '../../providers/calendar_sync_providers.dart';
import '../../providers/staff_providers.dart';
import '../../services/offline/connectivity_service.dart';
import '../../widgets/connectivity_indicator.dart';
import '../../widgets/deliveries_calendar_view.dart';
import '../../widgets/calendar_subscription_dialog.dart';
import '../../app/theme/brand_colors.dart';

class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final canViewAllDeliveries = ref.watch(canViewAllDeliveriesProvider);
    final canAssignDeliveries = ref.watch(canAssignDeliveriesProvider);
    final showAllDeliveries = ref.watch(allDeliveriesProvider);
    final connectivityAsync = ref.watch(connectivityStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        actions: [
          // Refresh connectivity button
          connectivityAsync.when(
            data: (status) {
              final isOffline = status == ConnectivityStatus.offline;
              return IconButton(
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isOffline ? Icons.wifi_off : Icons.refresh,
                        color: isOffline ? Colors.orange : null,
                      ),
                tooltip: isOffline ? 'Reconnect to WiFi' : 'Refresh connection',
                onPressed: _isRefreshing ? null : () => _refreshConnectivity(),
              );
            },
            loading: () => const SizedBox(width: 48),
            error: (_, __) => const SizedBox(width: 48),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Calendar options',
            onSelected: (value) {
              if (value == 'subscribe') {
                _showCalendarSubscriptionDialog(context);
              } else if (value == 'manual_sync') {
                _showCalendarSyncDialog(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'subscribe',
                child: Row(
                  children: [
                    const Icon(Icons.sync, size: 20, color: BrandColors.kakaBlue),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Subscribe to Calendar',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        Text(
                          'Auto-updates',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'manual_sync',
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload, size: 20, color: BrandColors.kakaBlue),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Manual Sync (Legacy)',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        Text(
                          'One-time sync',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (canViewAllDeliveries)
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filter deliveries',
              onSelected: (value) {
                if (value == 'toggle_filter') {
                  ref.read(allDeliveriesProvider.notifier).state =
                      !showAllDeliveries;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_filter',
                  child: Row(
                    children: [
                      Icon(
                        showAllDeliveries ? Icons.person : Icons.group,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(showAllDeliveries
                          ? 'Show My Deliveries'
                          : 'Show All Deliveries'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: const Column(
        children: [
          ConnectivityIndicator(),
          Expanded(
            child: DeliveriesCalendarView(),
          ),
        ],
      ),
      floatingActionButton: canAssignDeliveries
          ? FloatingActionButton(
              onPressed: () => context.push('/deliveries/add'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _refreshConnectivity() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      final connectivityService = ref.read(connectivityServiceProvider);

      // Force a connectivity check
      await connectivityService.checkConnectivity();

      // Show feedback
      if (mounted) {
        final status = await ref.read(connectivityStatusProvider.future);
        final isOnline = status == ConnectivityStatus.online;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(isOnline ? 'Connected to internet' : 'Still offline'),
              ],
            ),
            backgroundColor: isOnline ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('Error checking connection: $e'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _showCalendarSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CalendarSyncDialog(),
    );
  }

  Future<void> _showCalendarSubscriptionDialog(BuildContext dialogContext) async {
    // Get current staff
    var currentStaff = await ref.read(currentStaffProvider.future);

    if (!mounted) return;

    // If no staff record exists, check if user is an admin and create one
    if (currentStaff == null) {
      final currentUser = await ref.read(currentUserProvider.future);

      if (currentUser?.isAdmin ?? false) {
        // Auto-create staff record for admin
        final staffRepository = ref.read(staffRepositoryProvider);
        final firestore = FirebaseFirestore.instance;

        try {
          // Generate token before creating the document
          const uuid = Uuid();
          final token = uuid.v4();

          // Create staff record for admin with token
          final staffDoc = await firestore.collection('staff').add({
            'name': currentUser!.email.split('@')[0], // Use email username as name
            'uid': currentUser.uid,
            'role': 'admin',
            'assignedSchoolIds': [],
            'calendarToken': token, // Include token in initial creation
            'createdAt': Timestamp.fromDate(DateTime.now()),
          });

          // Fetch the newly created staff
          final result = await staffRepository.getStaffById(staffDoc.id);
          if (result.isSuccess && result.dataOrNull != null) {
            currentStaff = result.dataOrNull;
          }
        } catch (e) {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to create staff record: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else {
        // Regular user without staff record
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please link your account to a staff member first'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    if (currentStaff != null && mounted && context.mounted) {
      showDialog(
        context: context,
        builder: (context) => CalendarSubscriptionDialog(staff: currentStaff!),
      );
    }
  }
}

class _CalendarSyncDialog extends ConsumerStatefulWidget {
  const _CalendarSyncDialog();

  @override
  ConsumerState<_CalendarSyncDialog> createState() => _CalendarSyncDialogState();
}

class _CalendarSyncDialogState extends ConsumerState<_CalendarSyncDialog> {
  bool _isSyncing = false;
  String? _resultMessage;
  bool? _isSuccess;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.calendar_month, size: 24),
          SizedBox(width: 12),
          Text('Sync to Apple Calendar'),
        ],
      ),
      content: _isSyncing
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Syncing deliveries to your calendar...'),
              ],
            )
          : _resultMessage != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isSuccess ?? false ? Icons.check_circle : Icons.error,
                      size: 48,
                      color: _isSuccess ?? false ? Colors.green : Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _resultMessage!,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will sync all your deliveries to Apple Calendar.',
                      style: TextStyle(fontSize: 15),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'A new calendar called "BTS Deliveries" will be created.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'You can view and manage these events in the Apple Calendar app.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
      actions: _isSyncing
          ? []
          : _resultMessage != null
              ? [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _syncToCalendar,
                    child: const Text('Sync Now'),
                  ),
                ],
    );
  }

  Future<void> _syncToCalendar() async {
    setState(() {
      _isSyncing = true;
      _resultMessage = null;
      _isSuccess = null;
    });

    try {
      final service = ref.read(calendarSyncServiceProvider);

      // Request permissions
      final hasPermissions = await service.requestPermissions();
      if (!hasPermissions) {
        setState(() {
          _isSyncing = false;
          _resultMessage = 'Calendar permission denied. Please enable it in Settings.';
          _isSuccess = false;
        });
        return;
      }

      // Get all deliveries
      final deliveriesAsync = await ref.read(allDeliveriesListProvider.future);

      // Sync to calendar
      final result = await service.syncDeliveriesToCalendar(deliveriesAsync);

      setState(() {
        _isSyncing = false;
        _resultMessage = result.message;
        _isSuccess = result.allSucceeded || (!result.allFailed && result.successCount > 0);
      });
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _resultMessage = 'Failed to sync: $e';
        _isSuccess = false;
      });
    }
  }
}
