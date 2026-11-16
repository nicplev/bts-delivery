import 'dart:io';
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/result.dart';

abstract class StorageRepository {
  Future<Result<String>> uploadImage(String path, File file);
  Future<Result<String>> uploadImageBytes(String path, Uint8List bytes);
  Future<Result<String>> uploadFile(String path, File file);
  Future<Result<void>> deleteFile(String path);
  Future<Result<String>> getDownloadUrl(String path);
}

class FirebaseStorageRepository implements StorageRepository {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Future<Result<String>> uploadImage(String path, File file) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.putFile(file);
      final downloadUrl = await ref.getDownloadURL();
      return Result.success(downloadUrl);
    } catch (e) {
      return Result.failure('Failed to upload image: $e');
    }
  }

  @override
  Future<Result<String>> uploadImageBytes(String path, Uint8List bytes) async {
    try {
      debugPrint('Starting upload to path: $path');
      debugPrint('Storage bucket: ${_storage.bucket}');
      debugPrint('Platform: ${Platform.operatingSystem}');
      debugPrint('File size: ${bytes.length} bytes');

      final ref = _storage.ref().child(path);

      // Try without metadata first (sometimes metadata causes issues)
      debugPrint('Attempting upload without metadata...');
      try {
        await ref.putData(bytes);
        final downloadUrl = await ref.getDownloadURL();
        debugPrint('Upload successful!');
        return Result.success(downloadUrl);
      } catch (e) {
        debugPrint('Upload without metadata failed: $e');

        // Check if it's a 412 error
        if (e is FirebaseException && (e.message?.contains('412') ?? false)) {
          debugPrint('Detected 412 error, trying REST API workaround...');
          return await _uploadViaRestAPI(path, bytes);
        }

        // Try with metadata
        debugPrint('Attempting upload with metadata...');
        final metadata = SettableMetadata(
          contentType: 'image/png',
          customMetadata: {'uploadedBy': 'flutter-app'},
        );

        await ref.putData(bytes, metadata);
        final downloadUrl = await ref.getDownloadURL();
        debugPrint('Upload successful with metadata!');
        return Result.success(downloadUrl);
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (e is FirebaseException) {
        debugPrint('Firebase error code: ${e.code}');
        debugPrint('Firebase error message: ${e.message}');
        debugPrint('Firebase error plugin: ${e.plugin}');

        // If it's a 412 error, try REST API as last resort
        if (e.message?.contains('412') ?? false) {
          debugPrint(
              'Detected 412 error in final catch, trying REST API workaround...');
          return await _uploadViaRestAPI(path, bytes);
        }
      }
      return Result.failure('Failed to upload image: $e');
    }
  }

  /// Upload using Firebase Storage REST API (iOS workaround for 412 errors)
  Future<Result<String>> _uploadViaRestAPI(String path, Uint8List bytes) async {
    try {
      // Get auth token
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final token = await user.getIdToken();
      debugPrint('Got auth token');

      // Construct Firebase Storage REST API URL
      final bucket = _storage.bucket;
      final encodedPath = Uri.encodeComponent(path);

      // Use the upload URL format that Firebase Storage REST API expects
      final uploadUrl = Uri.parse(
          'https://firebasestorage.googleapis.com/v0/b/$bucket/o?name=$encodedPath');

      debugPrint('Uploading to: $uploadUrl');

      // Make direct HTTP POST request
      final response = await http.post(
        uploadUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'image/png',
        },
        body: bytes,
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Parse response to get download URL
        final responseData = json.decode(response.body) as Map<String, dynamic>;

        // Get download token from response
        final downloadTokens = responseData['downloadTokens'] as String?;

        if (downloadTokens != null) {
          // Construct download URL with token
          final downloadUrl =
              'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encodedPath?alt=media&token=$downloadTokens';
          debugPrint('Upload successful! Download URL: $downloadUrl');
          return Result.success(downloadUrl);
        } else {
          // Fallback: try to get download URL using SDK
          debugPrint(
              'No download token in response, trying SDK getDownloadURL...');
          final ref = _storage.ref().child(path);
          final downloadUrl = await ref.getDownloadURL();
          return Result.success(downloadUrl);
        }
      } else {
        throw Exception(
            'Upload failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('REST API upload error: $e');
      return Result.failure('Failed to upload via REST API: $e');
    }
  }

  @override
  Future<Result<String>> uploadFile(String path, File file) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.putFile(file);
      final downloadUrl = await ref.getDownloadURL();
      return Result.success(downloadUrl);
    } catch (e) {
      return Result.failure('Failed to upload file: $e');
    }
  }

  @override
  Future<Result<void>> deleteFile(String path) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.delete();
      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete file: $e');
    }
  }

  @override
  Future<Result<String>> getDownloadUrl(String path) async {
    try {
      final ref = _storage.ref().child(path);
      final downloadUrl = await ref.getDownloadURL();
      return Result.success(downloadUrl);
    } catch (e) {
      return Result.failure('Failed to get download URL: $e');
    }
  }
}
