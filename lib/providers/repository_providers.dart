import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/deliveries_repository.dart';
import '../../repositories/schools_repository.dart';
import '../../repositories/storage_repository.dart';
import '../services/photo_service.dart';
import '../services/permissions_service.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final deliveriesRepositoryProvider = Provider<DeliveriesRepository>((ref) {
  return FirebaseDeliveriesRepository();
});

final schoolsRepositoryProvider = Provider<SchoolsRepository>((ref) {
  final storageRepository = ref.watch(storageRepositoryProvider);
  return FirebaseSchoolsRepository(storageRepository);
});

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return FirebaseStorageRepository();
});

final photoServiceProvider = Provider<PhotoService>((ref) {
  final storageRepository = ref.watch(storageRepositoryProvider);
  return PhotoService(storageRepository);
});

final permissionsServiceProvider = Provider<PermissionsService>((ref) {
  return PermissionsService();
});