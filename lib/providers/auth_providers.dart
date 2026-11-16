import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/staff.dart';
import '../../models/user.dart';
import '../../repositories/auth_repository.dart';
import 'repository_providers.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.authStateChanges;
});

final currentStaffProvider = StreamProvider<Staff?>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.watchCurrentStaff();
});

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.watchCurrentUser();
});

final isAdminProvider = Provider<bool>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) => user?.isAdmin ?? false,
    loading: () => false,
    error: (_, __) => false,
  );
});

final isManagerProvider = Provider<bool>((ref) {
  final staffAsync = ref.watch(currentStaffProvider);
  return staffAsync.when(
    data: (staff) => staff?.hasManagerAccess ?? false,
    loading: () => false,
    error: (_, __) => false,
  );
});

// Provider for checking if user can view all deliveries
final canViewAllDeliveriesProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  final isManager = ref.watch(isManagerProvider);
  return isAdmin || isManager;
});

// Provider for checking if user can assign deliveries
final canAssignDeliveriesProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  final isManager = ref.watch(isManagerProvider);
  return isAdmin || isManager;
});

// Provider for checking if user can delete deliveries
final canDeleteDeliveriesProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  return isAdmin;
});

// Provider for checking if user can manage staff
final canManageStaffProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  return isAdmin;
});

// Provider for checking if user can edit school data
final canEditSchoolDataProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  final isManager = ref.watch(isManagerProvider);
  return isAdmin || isManager;
});

// Provider for checking if user can view sensitive data
final canViewSensitiveDataProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  final isManager = ref.watch(isManagerProvider);
  return isAdmin || isManager;
});

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  AuthNotifier(this._authRepository) : super(const AsyncValue.data(null));

  final AuthRepository _authRepository;

  Future<bool> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    final result = await _authRepository.signInWithEmailAndPassword(email, password);
    
    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> signUp(String email, String password) async {
    state = const AsyncValue.loading();
    final result = await _authRepository.createUserWithEmailAndPassword(email, password);
    
    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> linkToStaff(String staffId) async {
    state = const AsyncValue.loading();
    final result = await _authRepository.linkToStaff(staffId);
    
    return result.when(
      success: (_) {
        state = const AsyncValue.data(null);
        return true;
      },
      failure: (message, exception) {
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      },
    );
  }

  Future<void> signOut() async {
    await _authRepository.signOut();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return AuthNotifier(authRepository);
});