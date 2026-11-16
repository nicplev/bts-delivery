import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'result.dart';

class ImageService {
  static const int _maxWidth = 1600;
  static const int _maxHeight = 1600;
  static const int _quality = 85;

  static Future<Result<List<File>>> pickMultipleImages() async {
    try {
      // Check and request permissions
      final permissionResult = await _requestPermissions();
      if (!permissionResult.isSuccess) {
        return Result.failure(permissionResult.errorOrNull!);
      }

      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage();
      
      if (pickedFiles.isEmpty) {
        return const Result.success([]);
      }

      final compressedFiles = <File>[];
      for (final pickedFile in pickedFiles) {
        final compressedFile = await _compressImage(File(pickedFile.path));
        if (compressedFile.isSuccess) {
          compressedFiles.add(compressedFile.dataOrNull!);
        }
      }

      return Result.success(compressedFiles);
    } catch (e) {
      return Result.failure('Failed to pick images: $e');
    }
  }

  static Future<Result<File>> pickSingleImage({ImageSource source = ImageSource.gallery}) async {
    try {
      // Check and request permissions
      final permissionResult = await _requestPermissions();
      if (!permissionResult.isSuccess) {
        return Result.failure(permissionResult.errorOrNull!);
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);
      
      if (pickedFile == null) {
        return const Result.failure('No image selected');
      }

      final compressedFile = await _compressImage(File(pickedFile.path));
      return compressedFile;
    } catch (e) {
      return Result.failure('Failed to pick image: $e');
    }
  }

  static Future<Result<File>> _compressImage(File file) async {
    try {
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: _maxWidth,
        minHeight: _maxHeight,
        quality: _quality,
        format: CompressFormat.jpeg,
      );

      if (compressedBytes == null) {
        return const Result.failure('Failed to compress image');
      }

      // Create a new file with the compressed data
      final compressedFile = File('${file.path}_compressed.jpg');
      await compressedFile.writeAsBytes(compressedBytes);

      return Result.success(compressedFile);
    } catch (e) {
      return Result.failure('Failed to compress image: $e');
    }
  }

  static Future<Result<Uint8List>> compressImageBytes(Uint8List bytes) async {
    try {
      final compressedBytes = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: _maxWidth,
        minHeight: _maxHeight,
        quality: _quality,
        format: CompressFormat.jpeg,
      );

      return Result.success(compressedBytes);
    } catch (e) {
      return Result.failure('Failed to compress image bytes: $e');
    }
  }

  static Future<Result<void>> _requestPermissions() async {
    try {
      if (Platform.isIOS) {
        final status = await Permission.photos.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          return const Result.failure('Photo access permission is required to select images');
        }
      } else if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          return const Result.failure('Storage permission is required to select images');
        }
      }

      return const Result.success(null);
    } catch (e) {
      return Result.failure('Failed to request permissions: $e');
    }
  }
}