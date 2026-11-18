import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/staff_repository.dart';
import '../models/staff.dart';
import 'auth_providers.dart';

/// Provider for the staff repository
final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return FirebaseStaffRepository();
});

/// Sign-in details for every person, loaded only for super admins.
final teamDirectoryProvider = FutureProvider<TeamDirectory?>((ref) async {
  if (!ref.watch(isSuperAdminProvider)) return null;
  final result = await ref.watch(staffRepositoryProvider).getTeamAccounts();
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Could not load sign-in details');
  }
  return result.dataOrNull;
});

/// Provider to get all staff members
final allStaffProvider = FutureProvider<List<Staff>>((ref) async {
  final repository = ref.watch(staffRepositoryProvider);
  final result = await repository.getAllStaff();
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to get staff');
  }
  return result.dataOrNull!;
});

/// Provider to get a specific staff member by ID
final staffByIdProvider =
    FutureProvider.family<Staff, String>((ref, staffId) async {
  final repository = ref.watch(staffRepositoryProvider);
  final result = await repository.getStaffById(staffId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to get staff');
  }
  return result.dataOrNull!;
});

/// Provider to generate or get calendar token for a staff member
final calendarTokenProvider =
    FutureProvider.family<String, String>((ref, staffId) async {
  final repository = ref.watch(staffRepositoryProvider);
  final result = await repository.generateCalendarToken(staffId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to generate token');
  }
  return result.dataOrNull!;
});

/// Provider to regenerate calendar token (revokes old token)
final regenerateCalendarTokenProvider =
    FutureProvider.family<String, String>((ref, staffId) async {
  final repository = ref.watch(staffRepositoryProvider);
  final result = await repository.regenerateCalendarToken(staffId);
  if (result.isFailure) {
    throw Exception(result.errorOrNull ?? 'Failed to regenerate token');
  }
  return result.dataOrNull!;
});
