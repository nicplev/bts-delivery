import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/auth_repository.dart';
import '../repositories/deliveries_repository.dart';
import '../repositories/schools_repository.dart';
import '../repositories/storage_repository.dart';
import 'delivery_visit_provider.dart';
import '../models/delivery_visit.dart';
import '../services/photo_service.dart';
import '../services/permissions_service.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final deliveriesRepositoryProvider = Provider<DeliveriesRepository>((ref) {
  return FirebaseDeliveriesRepository();
});

// Background evidence uploads are explicit about which visit they update.
final baseSchoolsRepositoryProvider = Provider<SchoolsRepository>((ref) {
  return FirebaseSchoolsRepository();
});

final visitSchoolsRepositoryFactoryProvider =
    Provider<SchoolsRepository Function(DeliveryVisit)>((ref) {
  return (visit) => FirebaseSchoolsRepository(visit: visit);
});

final schoolsRepositoryProvider = Provider<SchoolsRepository>((ref) {
  final visit = ref.watch(activeDeliveryVisitProvider);
  if (visit == null) return ref.watch(baseSchoolsRepositoryProvider);
  return ref.watch(visitSchoolsRepositoryFactoryProvider)(visit);
}, dependencies: [activeDeliveryVisitProvider]);

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
