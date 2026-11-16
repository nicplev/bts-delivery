import 'package:hive/hive.dart';

part 'offline_models.g.dart';

/// Represents an operation that needs to be synced
@HiveType(typeId: 0)
class SyncQueueItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String operationType; // 'create', 'update', 'delete'

  @HiveField(2)
  final String entityType; // 'school', 'classroom', 'consumable', etc.

  @HiveField(3)
  final Map<String, dynamic> data;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final int retryCount;

  @HiveField(6)
  final String? errorMessage;

  @HiveField(7)
  final bool isProcessing;

  @HiveField(8)
  final String? userId;

  SyncQueueItem({
    required this.id,
    required this.operationType,
    required this.entityType,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
    this.errorMessage,
    this.isProcessing = false,
    this.userId,
  });

  SyncQueueItem copyWith({
    String? id,
    String? operationType,
    String? entityType,
    Map<String, dynamic>? data,
    DateTime? createdAt,
    int? retryCount,
    String? errorMessage,
    bool? isProcessing,
    String? userId,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      operationType: operationType ?? this.operationType,
      entityType: entityType ?? this.entityType,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
      isProcessing: isProcessing ?? this.isProcessing,
      userId: userId ?? this.userId,
    );
  }
}

/// Cached delivery data for offline access
@HiveType(typeId: 1)
class CachedDelivery extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String schoolId;

  @HiveField(2)
  final String schoolName;

  @HiveField(3)
  final String? schoolAddress;

  @HiveField(4)
  final DateTime lastSynced;

  @HiveField(5)
  final Map<String, dynamic> deliveryData;

  @HiveField(6)
  final String? assignedTo;

  @HiveField(7)
  final String status;

  CachedDelivery({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    this.schoolAddress,
    required this.lastSynced,
    required this.deliveryData,
    this.assignedTo,
    required this.status,
  });
}

/// Local photo that hasn't been uploaded yet
@HiveType(typeId: 2)
class LocalPhoto extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String localPath;

  @HiveField(2)
  final String schoolId;

  @HiveField(3)
  final String yearLevelId;

  @HiveField(4)
  final String classroomId;

  @HiveField(5)
  final DateTime createdAt;

  @HiveField(6)
  final bool isUploaded;

  @HiveField(7)
  final String? remotePath;

  @HiveField(8)
  final int? fileSize;

  LocalPhoto({
    required this.id,
    required this.localPath,
    required this.schoolId,
    required this.yearLevelId,
    required this.classroomId,
    required this.createdAt,
    this.isUploaded = false,
    this.remotePath,
    this.fileSize,
  });

  LocalPhoto copyWith({
    String? id,
    String? localPath,
    String? schoolId,
    String? yearLevelId,
    String? classroomId,
    DateTime? createdAt,
    bool? isUploaded,
    String? remotePath,
    int? fileSize,
  }) {
    return LocalPhoto(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      schoolId: schoolId ?? this.schoolId,
      yearLevelId: yearLevelId ?? this.yearLevelId,
      classroomId: classroomId ?? this.classroomId,
      createdAt: createdAt ?? this.createdAt,
      isUploaded: isUploaded ?? this.isUploaded,
      remotePath: remotePath ?? this.remotePath,
      fileSize: fileSize ?? this.fileSize,
    );
  }
}

/// Offline form draft
@HiveType(typeId: 3)
class FormDraft extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String formType; // 'classroom', 'consumable', 'contact', etc.

  @HiveField(2)
  final String entityId; // The ID of the entity being edited

  @HiveField(3)
  final Map<String, dynamic> formData;

  @HiveField(4)
  final DateTime lastModified;

  @HiveField(5)
  final String? schoolId;

  FormDraft({
    required this.id,
    required this.formType,
    required this.entityId,
    required this.formData,
    required this.lastModified,
    this.schoolId,
  });
}

/// Pending delivery completion (offline)
@HiveType(typeId: 5)
class PendingDeliveryCompletion extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String deliveryId;

  @HiveField(2)
  final String schoolId;

  @HiveField(3)
  final DateTime completedAt;

  @HiveField(4)
  final String? signatureLocalPath;

  @HiveField(5)
  final List<String> photoLocalPaths;

  @HiveField(6)
  final String? notes;

  @HiveField(7)
  final String? signedBy;

  @HiveField(8)
  final bool isUploaded;

  @HiveField(9)
  final String? completedBy;

  @HiveField(10)
  final Map<String, dynamic>? additionalData;

  PendingDeliveryCompletion({
    required this.id,
    required this.deliveryId,
    required this.schoolId,
    required this.completedAt,
    this.signatureLocalPath,
    this.photoLocalPaths = const [],
    this.notes,
    this.signedBy,
    this.isUploaded = false,
    this.completedBy,
    this.additionalData,
  });

  PendingDeliveryCompletion copyWith({
    String? id,
    String? deliveryId,
    String? schoolId,
    DateTime? completedAt,
    String? signatureLocalPath,
    List<String>? photoLocalPaths,
    String? notes,
    String? signedBy,
    bool? isUploaded,
    String? completedBy,
    Map<String, dynamic>? additionalData,
  }) {
    return PendingDeliveryCompletion(
      id: id ?? this.id,
      deliveryId: deliveryId ?? this.deliveryId,
      schoolId: schoolId ?? this.schoolId,
      completedAt: completedAt ?? this.completedAt,
      signatureLocalPath: signatureLocalPath ?? this.signatureLocalPath,
      photoLocalPaths: photoLocalPaths ?? this.photoLocalPaths,
      notes: notes ?? this.notes,
      signedBy: signedBy ?? this.signedBy,
      isUploaded: isUploaded ?? this.isUploaded,
      completedBy: completedBy ?? this.completedBy,
      additionalData: additionalData ?? this.additionalData,
    );
  }
}

/// App settings stored locally
@HiveType(typeId: 4)
class AppSettings extends HiveObject {
  @HiveField(0)
  final bool autoSync;

  @HiveField(1)
  final bool wifiOnlySync;

  @HiveField(2)
  final int syncInterval; // in minutes

  @HiveField(3)
  final bool compressImages;

  @HiveField(4)
  final int imageQuality; // 0-100

  @HiveField(5)
  final bool offlineModeEnabled;

  @HiveField(6)
  final DateTime? lastSyncTime;

  @HiveField(7)
  final int maxRetries;

  AppSettings({
    this.autoSync = true,
    this.wifiOnlySync = true,
    this.syncInterval = 15,
    this.compressImages = true,
    this.imageQuality = 80,
    this.offlineModeEnabled = true,
    this.lastSyncTime,
    this.maxRetries = 3,
  });

  AppSettings copyWith({
    bool? autoSync,
    bool? wifiOnlySync,
    int? syncInterval,
    bool? compressImages,
    int? imageQuality,
    bool? offlineModeEnabled,
    DateTime? lastSyncTime,
    int? maxRetries,
  }) {
    return AppSettings(
      autoSync: autoSync ?? this.autoSync,
      wifiOnlySync: wifiOnlySync ?? this.wifiOnlySync,
      syncInterval: syncInterval ?? this.syncInterval,
      compressImages: compressImages ?? this.compressImages,
      imageQuality: imageQuality ?? this.imageQuality,
      offlineModeEnabled: offlineModeEnabled ?? this.offlineModeEnabled,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      maxRetries: maxRetries ?? this.maxRetries,
    );
  }
}