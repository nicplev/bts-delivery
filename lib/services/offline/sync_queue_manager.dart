import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/offline/offline_models.dart';
import '../../models/school.dart';
import '../../repositories/schools_repository.dart';
import '../../providers/repository_providers.dart';
import '../../services/storage_service.dart';
import '../result.dart';
import 'connectivity_service.dart';
import 'offline_storage_service.dart';

class SyncQueueManager {
  final OfflineStorageService _offlineStorage;
  final ConnectivityService _connectivity;
  final SchoolsRepository _schoolsRepository;
  final StorageService _storageService;
  final Ref _ref;

  Timer? _syncTimer;
  bool _isSyncing = false;
  final _uuid = const Uuid();

  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  SyncQueueManager({
    required OfflineStorageService offlineStorage,
    required ConnectivityService connectivity,
    required SchoolsRepository schoolsRepository,
    required StorageService storageService,
    required Ref ref,
  })  : _offlineStorage = offlineStorage,
        _connectivity = connectivity,
        _schoolsRepository = schoolsRepository,
        _storageService = storageService,
        _ref = ref {
    _initialize();
  }

  void _initialize() {
    // Listen to connectivity changes
    _connectivity.statusStream.listen((status) {
      if (status == ConnectivityStatus.online && !_isSyncing) {
        // Start sync when coming back online
        syncPendingItems();
      }
    });

    // Set up periodic sync after a delay to ensure offline storage is initialized
    Future.delayed(const Duration(seconds: 1), () {
      _startPeriodicSync();
    });
  }

  void _startPeriodicSync() async {
    try {
      final settings = await _offlineStorage.getAppSettings();
      if (settings.autoSync) {
        _syncTimer?.cancel();
        _syncTimer = Timer.periodic(
          Duration(minutes: settings.syncInterval),
          (_) => syncPendingItems(),
        );
      }
    } catch (e) {
      // If settings aren't available yet, try again later
      Future.delayed(const Duration(seconds: 5), () {
        _startPeriodicSync();
      });
    }
  }

  // Queue operations for different entity types
  Future<void> queueSchoolUpdate(School school) async {
    final item = SyncQueueItem(
      id: _uuid.v4(),
      operationType: 'update',
      entityType: 'school',
      data: school.toJson(),
      createdAt: DateTime.now(),
      userId: _ref.read(userIdProvider),
    );
    await _offlineStorage.addToSyncQueue(item);
    if (_connectivity.isOnline) {
      syncPendingItems();
    }
  }

  Future<void> queueClassroomCreate({
    required String schoolId,
    required String yearLevelId,
    required Classroom classroom,
  }) async {
    final item = SyncQueueItem(
      id: _uuid.v4(),
      operationType: 'create',
      entityType: 'classroom',
      data: {
        'schoolId': schoolId,
        'yearLevelId': yearLevelId,
        'classroom': classroom.toJson(),
      },
      createdAt: DateTime.now(),
      userId: _ref.read(userIdProvider),
    );
    await _offlineStorage.addToSyncQueue(item);
    if (_connectivity.isOnline) {
      syncPendingItems();
    }
  }

  Future<void> queueConsumableUpdate({
    required String schoolId,
    required Consumable consumable,
  }) async {
    final item = SyncQueueItem(
      id: _uuid.v4(),
      operationType: 'update',
      entityType: 'consumable',
      data: {
        'schoolId': schoolId,
        'consumable': consumable.toJson(),
      },
      createdAt: DateTime.now(),
      userId: _ref.read(userIdProvider),
    );
    await _offlineStorage.addToSyncQueue(item);
    if (_connectivity.isOnline) {
      syncPendingItems();
    }
  }

  Future<void> queuePhotoUpload(LocalPhoto photo) async {
    final item = SyncQueueItem(
      id: photo.id,
      operationType: 'upload',
      entityType: 'photo',
      data: {
        'photoId': photo.id,
        'schoolId': photo.schoolId,
        'yearLevelId': photo.yearLevelId,
        'classroomId': photo.classroomId,
        'localPath': photo.localPath,
      },
      createdAt: photo.createdAt,
      userId: _ref.read(userIdProvider),
    );
    await _offlineStorage.addToSyncQueue(item);
    if (_connectivity.isOnline) {
      syncPendingItems();
    }
  }

  Future<void> queueSignOff({
    required String schoolId,
    required SignOff signOff,
  }) async {
    final item = SyncQueueItem(
      id: _uuid.v4(),
      operationType: 'create',
      entityType: 'signoff',
      data: {
        'schoolId': schoolId,
        'signOff': signOff.toJson(),
      },
      createdAt: DateTime.now(),
      userId: _ref.read(userIdProvider),
    );
    await _offlineStorage.addToSyncQueue(item);
    if (_connectivity.isOnline) {
      syncPendingItems();
    }
  }

  // Main sync function
  Future<void> syncPendingItems() async {
    if (_isSyncing || !_connectivity.isOnline) return;

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    try {
      final settings = await _offlineStorage.getAppSettings();

      // Check if we should only sync on WiFi
      if (settings.wifiOnlySync && !await _connectivity.isWifiConnected()) {
        _syncStatusController.add(SyncStatus.waitingForWifi);
        _isSyncing = false;
        return;
      }

      final pendingItems = await _offlineStorage.getPendingSyncItems();
      int failureCount = 0;

      for (final item in pendingItems) {
        if (!_connectivity.isOnline) break;

        // Mark item as processing
        await _offlineStorage.updateSyncItem(
          item.copyWith(isProcessing: true),
        );

        final success = await _processSyncItem(item);

        if (success) {
          await _offlineStorage.removeSyncItem(item.id);
        } else {
          failureCount++;
          // Update retry count
          await _offlineStorage.updateSyncItem(
            item.copyWith(
              isProcessing: false,
              retryCount: item.retryCount + 1,
            ),
          );
        }
      }

      // Update last sync time
      await _offlineStorage.updateAppSettings(
        (await _offlineStorage.getAppSettings()).copyWith(
          lastSyncTime: DateTime.now(),
        ),
      );

      _syncStatusController.add(
        failureCount > 0 ? SyncStatus.partial : SyncStatus.completed,
      );
    } catch (e) {
      _syncStatusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _processSyncItem(SyncQueueItem item) async {
    try {
      switch (item.entityType) {
        case 'school':
          return await _syncSchool(item);
        case 'classroom':
          return await _syncClassroom(item);
        case 'consumable':
          return await _syncConsumable(item);
        case 'photo':
          return await _syncPhoto(item);
        case 'signoff':
          return await _syncSignOff(item);
        case 'contact':
          return await _syncContact(item);
        case 'note':
          return await _syncNote(item);
        default:
          return false;
      }
    } catch (e) {
      await _offlineStorage.updateSyncItem(
        item.copyWith(errorMessage: e.toString()),
      );
      return false;
    }
  }

  Future<bool> _syncSchool(SyncQueueItem item) async {
    final school = School.fromJson(item.data);
    final result = await _schoolsRepository.updateSchool(school);
    return result.isSuccess;
  }

  Future<bool> _syncClassroom(SyncQueueItem item) async {
    final schoolId = item.data['schoolId'] as String;
    final yearLevelId = item.data['yearLevelId'] as String;
    final classroom = Classroom.fromJson(item.data['classroom']);

    Result result;
    if (item.operationType == 'create') {
      result = await _schoolsRepository.createClassroom(
          schoolId, yearLevelId, classroom);
    } else {
      result = await _schoolsRepository.updateClassroom(
          schoolId, yearLevelId, classroom);
    }
    return result.isSuccess;
  }

  Future<bool> _syncConsumable(SyncQueueItem item) async {
    final schoolId = item.data['schoolId'] as String;
    final consumable = Consumable.fromJson(item.data['consumable']);

    Result result;
    if (item.operationType == 'create') {
      result = await _schoolsRepository.createConsumable(schoolId, consumable);
    } else {
      result = await _schoolsRepository.updateConsumable(schoolId, consumable);
    }
    return result.isSuccess;
  }

  Future<bool> _syncPhoto(SyncQueueItem item) async {
    final photoId = item.data['photoId'] as String;
    final localPath = item.data['localPath'] as String;
    final schoolId = item.data['schoolId'] as String;
    final yearLevelId = item.data['yearLevelId'] as String;
    final classroomId = item.data['classroomId'] as String;

    // Upload photo to Firebase Storage
    final remotePath =
        'schools/$schoolId/classrooms/$classroomId/${_uuid.v4()}.jpg';
    final result = await _storageService.uploadFile(localPath, remotePath);

    if (result.isSuccess) {
      // Mark photo as uploaded in local storage
      await _offlineStorage.markPhotoAsUploaded(photoId, result.dataOrNull!);

      // Add photo to classroom in Firestore
      final photo = Photo(
        id: photoId,
        storagePath: result.dataOrNull!,
        uploadedAt: DateTime.now(),
      );

      final firestoreResult = await _schoolsRepository.addClassroomPhoto(
        schoolId,
        yearLevelId,
        classroomId,
        photo,
      );
      return firestoreResult.isSuccess;
    }
    return false;
  }

  Future<bool> _syncSignOff(SyncQueueItem item) async {
    final schoolId = item.data['schoolId'] as String;
    final signOff = SignOff.fromJson(item.data['signOff']);

    final result =
        await _schoolsRepository.createOrUpdateSignOff(schoolId, signOff);
    return result.isSuccess;
  }

  Future<bool> _syncContact(SyncQueueItem item) async {
    final schoolId = item.data['schoolId'] as String;
    final contact = Contact.fromJson(item.data['contact']);

    Result result;
    if (item.operationType == 'create') {
      result = await _schoolsRepository.createContact(schoolId, contact);
    } else if (item.operationType == 'update') {
      result = await _schoolsRepository.updateContact(schoolId, contact);
    } else {
      result = await _schoolsRepository.deleteContact(schoolId, contact.id);
    }
    return result.isSuccess;
  }

  Future<bool> _syncNote(SyncQueueItem item) async {
    final schoolId = item.data['schoolId'] as String;
    final note = Note.fromJson(item.data['note']);

    Result result;
    if (item.operationType == 'create') {
      result = await _schoolsRepository.createNote(schoolId, note);
    } else {
      result = await _schoolsRepository.deleteNote(schoolId, note.id);
    }
    return result.isSuccess;
  }

  // Manual sync trigger
  Future<void> triggerManualSync() async {
    await syncPendingItems();
  }

  // Get sync statistics
  Future<Map<String, dynamic>> getSyncStats() async {
    final pendingItems = await _offlineStorage.getPendingSyncItems();
    final storageStats = await _offlineStorage.getStorageStats();
    final settings = await _offlineStorage.getAppSettings();

    return {
      'pendingItems': pendingItems.length,
      'isSyncing': _isSyncing,
      'isOnline': _connectivity.isOnline,
      'lastSyncTime': settings.lastSyncTime,
      ...storageStats,
    };
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncStatusController.close();
  }
}

// Sync status enum
enum SyncStatus {
  idle,
  syncing,
  completed,
  partial,
  error,
  waitingForWifi,
}

// Provider for user ID (placeholder - should be replaced with actual auth provider)
final userIdProvider = Provider<String?>((ref) => null);

// Provider for sync queue manager
final syncQueueManagerProvider = FutureProvider<SyncQueueManager>((ref) async {
  // Wait for offline storage to be initialized
  await ref.watch(offlineStorageInitProvider.future);

  final offlineStorage = ref.watch(offlineStorageServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final schoolsRepository = ref.watch(schoolsRepositoryProvider);
  final storageService = ref.watch(storageServiceProvider);

  final manager = SyncQueueManager(
    offlineStorage: offlineStorage,
    connectivity: connectivity,
    schoolsRepository: schoolsRepository,
    storageService: storageService,
    ref: ref,
  );

  ref.onDispose(() => manager.dispose());
  return manager;
});

// Provider for sync status
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  try {
    final manager = await ref.watch(syncQueueManagerProvider.future);
    yield* manager.syncStatusStream;
  } catch (e) {
    yield SyncStatus.error;
  }
});

// Provider for sync statistics
final syncStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final manager = await ref.watch(syncQueueManagerProvider.future);
    return await manager.getSyncStats();
  } catch (e) {
    return {
      'pendingItems': 0,
      'isSyncing': false,
      'isOnline': false,
      'lastSyncTime': null,
    };
  }
});
