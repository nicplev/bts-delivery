import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../repositories/storage_repository.dart';
import '../services/image_service.dart';
import '../services/result.dart';
import '../widgets/design/design.dart';

class PhotoService {
  final ImagePicker _picker = ImagePicker();
  final StorageRepository _storageRepository;

  PhotoService(this._storageRepository);

  /// Glass source picker over the tab bar (root navigator): one card of
  /// icon rows and a Cancel capsule. Returns null when dismissed.
  Future<T?> _choose<T>(
    BuildContext context, {
    required String title,
    required List<(T, IconData, String)> options,
  }) {
    return showAppGlassSheet<T>(
      context: context,
      title: title,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppGroupedList(
              separatorIndent: 57,
              children: [
                for (final (value, icon, label) in options)
                  AppListRow(
                    icon: icon,
                    title: label,
                    showChevron: false,
                    onTap: () => Navigator.pop(sheetContext, value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AppSecondaryButton(
              label: 'Cancel',
              onPressed: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a dialog to choose between camera and gallery
  Future<File?> pickImage(BuildContext context) async {
    final source = await _choose<ImageSource>(
      context,
      title: 'Add photo',
      options: const [
        (ImageSource.camera, AppIcons.photos, 'Take photo'),
        (ImageSource.gallery, AppIcons.gallery, 'Choose from gallery'),
      ],
    );

    if (source == null) return null;

    // Request permission
    final hasPermission = await _requestPermission(source);
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera
                  ? 'Camera permission is required to take photos'
                  : 'Photo library permission is required to select photos',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return null;
    }

    // Pick image
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return null;

      // Compress image
      final compressedFile = await _compressImage(File(image.path));
      return compressedFile;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
      return null;
    }
  }

  /// Pick multiple images from gallery
  Future<List<File>> pickMultipleImages(BuildContext context) async {
    // Request permission
    final hasPermission = await _requestPermission(ImageSource.gallery);
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Photo library permission is required to select photos'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return [];
    }

    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (images.isEmpty) return [];

      // Compress all images
      final List<File> compressedFiles = [];
      for (final image in images) {
        final compressed = await _compressImage(File(image.path));
        if (compressed != null) {
          compressedFiles.add(compressed);
        }
      }

      return compressedFiles;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking images: $e')),
        );
      }
      return [];
    }
  }

  /// Upload a photo to Firebase Storage
  Future<Result<String>> uploadPhoto(
    String storagePath,
    File file,
  ) async {
    try {
      return await _storageRepository.uploadImage(storagePath, file);
    } catch (e) {
      return Result.failure('Failed to upload photo: $e');
    }
  }

  /// Request camera or photo library permission
  Future<bool> _requestPermission(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      return status.isGranted;
    } else {
      if (Platform.isIOS) {
        final status = await Permission.photos.request();
        return status.isGranted || status.isLimited;
      } else {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    }
  }

  /// Compress image to reduce file size
  Future<File?> _compressImage(File file) async {
    try {
      final filePath = file.absolute.path;
      final lastIndex = filePath.lastIndexOf('.');
      final splitted = filePath.substring(0, lastIndex);
      final outPath = '${splitted}_compressed.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        outPath,
        quality: 85,
        minWidth: 1920,
        minHeight: 1920,
      );

      if (result == null) return file;
      return File(result.path);
    } catch (e) {
      debugPrint('Error compressing image: $e');
      return file;
    }
  }

  /// Pick a file (image or PDF) for school map
  /// Shows options: Take Photo, Choose from Gallery, Choose File
  Future<File?> pickSchoolMapFile(BuildContext context) async {
    final choice = await _choose<String>(
      context,
      title: 'Add school map',
      options: const [
        ('camera', AppIcons.photos, 'Take photo'),
        ('gallery', AppIcons.gallery, 'Choose from gallery'),
        ('file', AppIcons.document, 'Choose file (PDF or image)'),
      ],
    );

    if (choice == null) return null;

    try {
      if (choice == 'camera' || choice == 'gallery') {
        // Use image picker for camera/gallery
        final source =
            choice == 'camera' ? ImageSource.camera : ImageSource.gallery;

        // Request permission
        final hasPermission = await _requestPermission(source);
        if (!hasPermission) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  source == ImageSource.camera
                      ? 'Camera permission is required to take photos'
                      : 'Photo library permission is required to select photos',
                ),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return null;
        }

        final XFile? image = await _picker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );

        if (image == null) return null;

        // Compress image
        final compressedFile = await _compressImage(File(image.path));
        return compressedFile;
      } else if (choice == 'file') {
        // Use file picker for documents
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        );

        if (result != null && result.files.single.path != null) {
          return File(result.files.single.path!);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting file: $e')),
        );
      }
    }

    return null;
  }

  /// Picks a school logo with the same glass sheet as photos (camera or
  /// library) and returns it as a small JPEG ready to upload (longest side
  /// 512 px, quality 85). Images only. Null when cancelled or unusable (the
  /// reason is shown).
  Future<Uint8List?> pickSchoolLogo(BuildContext context) async {
    final source = await _choose<ImageSource>(
      context,
      title: 'Add school logo',
      options: const [
        (ImageSource.camera, AppIcons.photos, 'Take photo'),
        (ImageSource.gallery, AppIcons.gallery, 'Choose from gallery'),
      ],
    );
    if (source == null) return null;

    final hasPermission = await _requestPermission(source);
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera
                  ? 'Camera permission is required to take photos'
                  : 'Photo library permission is required to select photos',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return null;
    }

    try {
      // The picker applies the photo's orientation; the logo is then
      // flattened, resized and compressed by the image service.
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (image == null) return null;
      final prepared =
          await ImageService.prepareSchoolLogo(await image.readAsBytes());
      if (prepared.isSuccess) return prepared.dataOrNull;
    } catch (e) {
      debugPrint('Error preparing school logo: $e');
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t use that image. Try another one.'),
        ),
      );
    }
    return null;
  }

  /// Upload a school map file to Firebase Storage
  Future<Result<String>> uploadSchoolMap(
    String storagePath,
    File file,
  ) async {
    try {
      return await _storageRepository.uploadFile(storagePath, file);
    } catch (e) {
      return Result.failure('Failed to upload school map: $e');
    }
  }
}
