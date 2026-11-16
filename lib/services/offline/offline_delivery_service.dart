import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/offline/offline_models.dart';
import 'connectivity_service.dart';

/// Service for handling delivery completions while offline
class OfflineDeliveryService {
  static const String _pendingCompletionsBox = 'pending_delivery_completions';

  final ConnectivityService _connectivity;
  final Uuid _uuid = const Uuid();

  OfflineDeliveryService(this._connectivity);

  /// Save delivery completion for later upload when offline
  Future<String> saveDeliveryCompletion({
    required String deliveryId,
    required String schoolId,
    required String completedBy,
    File? signatureFile,
    List<File>? photoFiles,
    String? notes,
    String? signedBy,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final completionId = _uuid.v4();
      final isOnline = _connectivity.isOnline;

      // Save signature to local storage if provided
      String? signatureLocalPath;
      if (signatureFile != null) {
        signatureLocalPath = await _saveFileLocally(
          signatureFile,
          'signature_${deliveryId}_${DateTime.now().millisecondsSinceEpoch}.png',
        );
      }

      // Save photos to local storage if provided
      final List<String> photoLocalPaths = [];
      if (photoFiles != null && photoFiles.isNotEmpty) {
        for (int i = 0; i < photoFiles.length; i++) {
          final photoPath = await _saveFileLocally(
            photoFiles[i],
            'photo_${deliveryId}_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          photoLocalPaths.add(photoPath);
        }
      }

      // Create pending completion record
      final completion = PendingDeliveryCompletion(
        id: completionId,
        deliveryId: deliveryId,
        schoolId: schoolId,
        completedAt: DateTime.now(),
        signatureLocalPath: signatureLocalPath,
        photoLocalPaths: photoLocalPaths,
        notes: notes,
        signedBy: signedBy,
        completedBy: completedBy,
        additionalData: additionalData,
        isUploaded: false,
      );

      // Save to Hive
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);
      await box.put(completionId, completion);

      if (kDebugMode) {
        debugPrint('Saved delivery completion offline: $completionId');
        debugPrint('  - Signature: ${signatureLocalPath != null ? "Yes" : "No"}');
        debugPrint('  - Photos: ${photoLocalPaths.length}');
        debugPrint('  - Online: $isOnline');
      }

      return completionId;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving delivery completion: $e');
      }
      rethrow;
    }
  }

  /// Get all pending delivery completions
  Future<List<PendingDeliveryCompletion>> getPendingCompletions() async {
    try {
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);
      return box.values.where((c) => !c.isUploaded).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting pending completions: $e');
      }
      return [];
    }
  }

  /// Get pending completions for a specific delivery
  Future<PendingDeliveryCompletion?> getPendingCompletionForDelivery(String deliveryId) async {
    try {
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);
      return box.values.firstWhere(
        (c) => c.deliveryId == deliveryId && !c.isUploaded,
        orElse: () => throw StateError('No pending completion found'),
      );
    } catch (e) {
      return null;
    }
  }

  /// Mark completion as uploaded
  Future<void> markAsUploaded(String completionId) async {
    try {
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);
      final completion = box.get(completionId);

      if (completion != null) {
        final updated = completion.copyWith(isUploaded: true);
        await box.put(completionId, updated);

        if (kDebugMode) {
          debugPrint('Marked completion as uploaded: $completionId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error marking completion as uploaded: $e');
      }
    }
  }

  /// Delete a pending completion
  Future<void> deletePendingCompletion(String completionId) async {
    try {
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);
      final completion = box.get(completionId);

      // Delete local files
      if (completion != null) {
        if (completion.signatureLocalPath != null) {
          await _deleteFileIfExists(completion.signatureLocalPath!);
        }
        for (final photoPath in completion.photoLocalPaths) {
          await _deleteFileIfExists(photoPath);
        }
      }

      await box.delete(completionId);

      if (kDebugMode) {
        debugPrint('Deleted pending completion: $completionId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting pending completion: $e');
      }
    }
  }

  /// Clear all uploaded completions (cleanup)
  Future<void> clearUploadedCompletions() async {
    try {
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);
      final uploaded = box.values.where((c) => c.isUploaded).toList();

      for (final completion in uploaded) {
        await deletePendingCompletion(completion.id);
      }

      if (kDebugMode) {
        debugPrint('Cleared ${uploaded.length} uploaded completions');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error clearing uploaded completions: $e');
      }
    }
  }

  /// Get count of pending uploads
  Future<int> getPendingCount() async {
    final pending = await getPendingCompletions();
    return pending.length;
  }

  /// Check if a delivery has a pending completion
  Future<bool> hasPendingCompletion(String deliveryId) async {
    final completion = await getPendingCompletionForDelivery(deliveryId);
    return completion != null;
  }

  /// Save file to local app directory
  Future<String> _saveFileLocally(File file, String filename) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final localDir = Directory('${directory.path}/pending_uploads');

      // Create directory if it doesn't exist
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      final localPath = '${localDir.path}/$filename';
      await file.copy(localPath);

      return localPath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving file locally: $e');
      }
      rethrow;
    }
  }

  /// Delete file if it exists
  Future<void> _deleteFileIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting file: $e');
      }
    }
  }

  /// Get signature file for a completion
  Future<File?> getSignatureFile(String completionId) async {
    try {
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);
      final completion = box.get(completionId);

      if (completion?.signatureLocalPath != null) {
        final file = File(completion!.signatureLocalPath!);
        if (await file.exists()) {
          return file;
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting signature file: $e');
      }
      return null;
    }
  }

  /// Get photo files for a completion
  Future<List<File>> getPhotoFiles(String completionId) async {
    try {
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);
      final completion = box.get(completionId);

      if (completion != null) {
        final List<File> files = [];
        for (final path in completion.photoLocalPaths) {
          final file = File(path);
          if (await file.exists()) {
            files.add(file);
          }
        }
        return files;
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting photo files: $e');
      }
      return [];
    }
  }

  /// Get storage size of pending completions
  Future<int> getPendingStorageSize() async {
    try {
      int totalSize = 0;
      final box = await Hive.openBox<PendingDeliveryCompletion>(_pendingCompletionsBox);

      for (final completion in box.values.where((c) => !c.isUploaded)) {
        // Check signature file
        if (completion.signatureLocalPath != null) {
          final file = File(completion.signatureLocalPath!);
          if (await file.exists()) {
            totalSize += await file.length();
          }
        }

        // Check photo files
        for (final photoPath in completion.photoLocalPaths) {
          final file = File(photoPath);
          if (await file.exists()) {
            totalSize += await file.length();
          }
        }
      }

      return totalSize;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error calculating storage size: $e');
      }
      return 0;
    }
  }

  /// Format storage size for display
  String formatStorageSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
