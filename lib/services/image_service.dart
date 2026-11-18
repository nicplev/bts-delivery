import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
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

  /// Longest side of an uploaded school logo, in pixels.
  static const int schoolLogoMaxSide = 512;

  /// Largest school logo the storage rules accept.
  static const int schoolLogoMaxBytes = 2 * 1024 * 1024;

  /// Turns a picked image into a small JPEG for a school logo: scaled so its
  /// longest side is at most [maxSide] (never enlarged), drawn on white so a
  /// transparent PNG logo doesn't turn black as a JPEG, then encoded at
  /// [quality]. [encodeJpeg] defaults to the native compressor (tests replace
  /// it).
  static Future<Result<Uint8List>> prepareSchoolLogo(
    Uint8List bytes, {
    int maxSide = schoolLogoMaxSide,
    int quality = _quality,
    Future<Uint8List> Function(Uint8List png, int width, int height, int quality)?
        encodeJpeg,
  }) async {
    ui.Codec? codec;
    ui.Image? frame;
    ui.Image? flattened;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final sourceWidth = descriptor.width;
      final sourceHeight = descriptor.height;
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        descriptor.dispose();
        buffer.dispose();
        return const Result.failure('This image can’t be used');
      }
      final longest = sourceWidth > sourceHeight ? sourceWidth : sourceHeight;
      final scale = longest > maxSide ? maxSide / longest : 1.0;
      final width = (sourceWidth * scale).round().clamp(1, maxSide);
      final height = (sourceHeight * scale).round().clamp(1, maxSide);
      codec = await descriptor.instantiateCodec(
          targetWidth: width, targetHeight: height);
      frame = (await codec.getNextFrame()).image;
      descriptor.dispose();
      buffer.dispose();

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final bounds =
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      canvas.drawRect(bounds, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      canvas.drawImageRect(
        frame,
        ui.Rect.fromLTWH(
            0, 0, frame.width.toDouble(), frame.height.toDouble()),
        bounds,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      flattened = await picture.toImage(width, height);
      picture.dispose();
      final png = await flattened.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        return const Result.failure('This image can’t be used');
      }
      final jpeg = await (encodeJpeg ?? _encodeJpeg)(
          png.buffer.asUint8List(), width, height, quality);
      if (jpeg.isEmpty || jpeg.length > schoolLogoMaxBytes) {
        return const Result.failure('This image can’t be used');
      }
      return Result.success(jpeg);
    } catch (e) {
      return Result.failure('Failed to prepare the logo: $e');
    } finally {
      frame?.dispose();
      flattened?.dispose();
      codec?.dispose();
    }
  }

  static Future<Uint8List> _encodeJpeg(
          Uint8List png, int width, int height, int quality) =>
      FlutterImageCompress.compressWithList(
        png,
        minWidth: width,
        minHeight: height,
        quality: quality,
        format: CompressFormat.jpeg,
      );

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