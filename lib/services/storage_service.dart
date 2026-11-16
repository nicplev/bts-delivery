import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'result.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<Result<String>> uploadFile(String localPath, String remotePath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return Result.failure('File not found: $localPath');
      }

      final ref = _storage.ref(remotePath);
      final uploadTask = ref.putFile(file);

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return Result.success(downloadUrl);
    } catch (e) {
      return Result.failure('Failed to upload file: $e');
    }
  }

  Future<Result<String>> uploadImageBytes(
      String remotePath, List<int> bytes) async {
    try {
      final ref = _storage.ref(remotePath);
      final uploadTask = ref.putData(Uint8List.fromList(bytes));

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return Result.success(downloadUrl);
    } catch (e) {
      return Result.failure('Failed to upload image: $e');
    }
  }

  Future<Result<void>> deleteFile(String remotePath) async {
    try {
      final ref = _storage.ref(remotePath);
      await ref.delete();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete file: $e');
    }
  }

  Future<Result<String>> getDownloadUrl(String remotePath) async {
    try {
      final ref = _storage.ref(remotePath);
      final url = await ref.getDownloadURL();
      return Result.success(url);
    } catch (e) {
      return Result.failure('Failed to get download URL: $e');
    }
  }

  Future<Result<List<String>>> listFiles(String path) async {
    try {
      final ref = _storage.ref(path);
      final result = await ref.listAll();

      final urls = await Future.wait(
        result.items.map((item) => item.getDownloadURL()),
      );

      return Result.success(urls);
    } catch (e) {
      return Result.failure('Failed to list files: $e');
    }
  }
}

// Provider for storage service
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});
