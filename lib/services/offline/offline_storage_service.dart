import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/offline/offline_models.dart';
import '../../models/school.dart';

class OfflineStorageService {
  static const String syncQueueBox = 'sync_queue';
  static const String cachedDeliveriesBox = 'cached_deliveries';
  static const String localPhotosBox = 'local_photos';
  static const String formDraftsBox = 'form_drafts';
  static const String appSettingsBox = 'app_settings';
  static const String cachedSchoolDataBox = 'cached_school_data';

  late Box<SyncQueueItem> _syncQueue;
  late Box<CachedDelivery> _cachedDeliveries;
  late Box<LocalPhoto> _localPhotos;
  late Box<FormDraft> _formDrafts;
  late Box<AppSettings> _appSettings;
  late Box<Map<String, dynamic>> _cachedSchoolData;

  Future<void> initialize() async {
    try {
      // Only initialize Hive if it hasn't been initialized yet
      if (!Hive.isBoxOpen(syncQueueBox)) {
        // Hive.initFlutter() might have been called in main(), so check if it's needed
        try {
          await Hive.initFlutter();
        } catch (e) {
          // Hive is already initialized, continue
        }
      }

      // Register adapters
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(SyncQueueItemAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(CachedDeliveryAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(LocalPhotoAdapter());
      }
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(FormDraftAdapter());
      }
      if (!Hive.isAdapterRegistered(4)) {
        Hive.registerAdapter(AppSettingsAdapter());
      }
      if (!Hive.isAdapterRegistered(5)) {
        Hive.registerAdapter(PendingDeliveryCompletionAdapter());
      }

      // Open boxes
      _syncQueue = await Hive.openBox<SyncQueueItem>(syncQueueBox);
      _cachedDeliveries = await Hive.openBox<CachedDelivery>(cachedDeliveriesBox);
      _localPhotos = await Hive.openBox<LocalPhoto>(localPhotosBox);
      _formDrafts = await Hive.openBox<FormDraft>(formDraftsBox);
      _appSettings = await Hive.openBox<AppSettings>(appSettingsBox);
      _cachedSchoolData = await Hive.openBox<Map<String, dynamic>>(cachedSchoolDataBox);

      // Initialize default settings if not exists
      if (_appSettings.isEmpty) {
        await _appSettings.put('default', AppSettings());
      }
    } catch (e) {
      // If initialization fails, still try to set up boxes with fallback
      try {
        _syncQueue = await Hive.openBox<SyncQueueItem>(syncQueueBox);
        _cachedDeliveries = await Hive.openBox<CachedDelivery>(cachedDeliveriesBox);
        _localPhotos = await Hive.openBox<LocalPhoto>(localPhotosBox);
        _formDrafts = await Hive.openBox<FormDraft>(formDraftsBox);
        _appSettings = await Hive.openBox<AppSettings>(appSettingsBox);
        _cachedSchoolData = await Hive.openBox<Map<String, dynamic>>(cachedSchoolDataBox);
        
        // Initialize default settings if not exists
        if (_appSettings.isEmpty) {
          await _appSettings.put('default', AppSettings());
        }
      } catch (fallbackError) {
        // If we can't open boxes at all, rethrow the original error
        rethrow;
      }
    }
  }

  // Sync Queue Operations
  Future<void> addToSyncQueue(SyncQueueItem item) async {
    await _syncQueue.put(item.id, item);
  }

  Future<List<SyncQueueItem>> getPendingSyncItems() async {
    return _syncQueue.values
        .where((item) => !item.isProcessing)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> updateSyncItem(SyncQueueItem item) async {
    await _syncQueue.put(item.id, item);
  }

  Future<void> removeSyncItem(String id) async {
    await _syncQueue.delete(id);
  }

  Future<void> clearCompletedSyncItems() async {
    final keysToRemove = <String>[];
    _syncQueue.toMap().forEach((key, value) {
      if (value.retryCount >= 3 || value.isProcessing) {
        keysToRemove.add(key);
      }
    });
    await _syncQueue.deleteAll(keysToRemove);
  }

  // Cached Deliveries Operations
  Future<void> cacheDelivery(School school) async {
    final cached = CachedDelivery(
      id: school.id,
      schoolId: school.id,
      schoolName: school.name,
      schoolAddress: school.address,
      lastSynced: DateTime.now(),
      deliveryData: {
        'id': school.id,
        'name': school.name,
        'address': school.address,
        'createdAt': school.createdAt.toIso8601String(),
        'isSignedOff': school.isSignedOff,
        'lastSignOffDate': school.lastSignOffDate?.toIso8601String(),
        'signedBy': school.signedBy,
      },
      status: school.isSignedOff ? 'completed' : 'pending',
    );
    await _cachedDeliveries.put(school.id, cached);
  }

  Future<List<CachedDelivery>> getCachedDeliveries() async {
    return _cachedDeliveries.values.toList();
  }

  Future<CachedDelivery?> getCachedDelivery(String id) async {
    return _cachedDeliveries.get(id);
  }

  Future<void> clearDeliveryCache() async {
    await _cachedDeliveries.clear();
  }

  // Local Photos Operations
  Future<void> addLocalPhoto(LocalPhoto photo) async {
    await _localPhotos.put(photo.id, photo);
  }

  Future<List<LocalPhoto>> getUnuploadedPhotos() async {
    return _localPhotos.values
        .where((photo) => !photo.isUploaded)
        .toList();
  }

  Future<List<LocalPhoto>> getPhotosForClassroom(
    String schoolId,
    String yearLevelId,
    String classroomId,
  ) async {
    return _localPhotos.values
        .where((photo) =>
            photo.schoolId == schoolId &&
            photo.yearLevelId == yearLevelId &&
            photo.classroomId == classroomId)
        .toList();
  }

  Future<void> markPhotoAsUploaded(String photoId, String remotePath) async {
    final photo = _localPhotos.get(photoId);
    if (photo != null) {
      await _localPhotos.put(
        photoId,
        photo.copyWith(isUploaded: true, remotePath: remotePath),
      );
    }
  }

  Future<void> deleteLocalPhoto(String photoId) async {
    final photo = _localPhotos.get(photoId);
    if (photo != null) {
      // Delete the actual file
      try {
        final file = File(photo.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // Ignore file deletion errors
      }
      await _localPhotos.delete(photoId);
    }
  }

  // Form Drafts Operations
  Future<void> saveFormDraft(FormDraft draft) async {
    await _formDrafts.put(draft.id, draft);
  }

  Future<FormDraft?> getFormDraft(String formType, String entityId) async {
    try {
      return _formDrafts.values.firstWhere(
        (draft) => draft.formType == formType && draft.entityId == entityId,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteFormDraft(String id) async {
    await _formDrafts.delete(id);
  }

  Future<List<FormDraft>> getAllFormDrafts() async {
    return _formDrafts.values.toList();
  }

  // App Settings Operations
  Future<AppSettings> getAppSettings() async {
    return _appSettings.get('default') ?? AppSettings();
  }

  Future<void> updateAppSettings(AppSettings settings) async {
    await _appSettings.put('default', settings);
  }

  // Cached School Data Operations
  Future<void> cacheSchoolData(String schoolId, Map<String, dynamic> data) async {
    await _cachedSchoolData.put(schoolId, data);
  }

  Future<Map<String, dynamic>?> getCachedSchoolData(String schoolId) async {
    return _cachedSchoolData.get(schoolId);
  }

  // Clear all data
  Future<void> clearAllData() async {
    await _syncQueue.clear();
    await _cachedDeliveries.clear();
    await _localPhotos.clear();
    await _formDrafts.clear();
    await _cachedSchoolData.clear();
    // Don't clear app settings
  }

  // Get storage statistics
  Future<Map<String, int>> getStorageStats() async {
    int totalSize = 0;
    
    // Try to get directory size (may fail on some platforms)
    try {
      // Use any initialized box to get the Hive directory path
      String? hivePath;
      if (_syncQueue.isOpen) {
        hivePath = _syncQueue.path;
      } else if (_appSettings.isOpen) {
        hivePath = _appSettings.path;
      }
      
      if (hivePath != null) {
        final hiveDir = Directory(hivePath).parent;
        if (await hiveDir.exists()) {
          await for (var entity in hiveDir.list(recursive: true)) {
            if (entity is File) {
              totalSize += await entity.length();
            }
          }
        }
      }
    } catch (e) {
      // If we can't get directory size, just use 0
      totalSize = 0;
    }

    return {
      'syncQueueCount': _syncQueue.length,
      'cachedDeliveriesCount': _cachedDeliveries.length,
      'localPhotosCount': _localPhotos.length,
      'unuploadedPhotosCount': 
          _localPhotos.values.where((p) => !p.isUploaded).length,
      'formDraftsCount': _formDrafts.length,
      'totalSizeBytes': totalSize,
    };
  }

  void dispose() {
    Hive.close();
  }
}

// Provider for offline storage service
final offlineStorageServiceProvider = Provider<OfflineStorageService>((ref) {
  final service = OfflineStorageService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Provider to initialize offline storage
final offlineStorageInitProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(offlineStorageServiceProvider);
  await service.initialize();
});