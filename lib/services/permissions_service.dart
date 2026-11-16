import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  /// Request essential permissions on first app launch
  Future<void> requestInitialPermissions() async {
    // Request camera permission
    await _requestCameraPermission();

    // Request photo library permission
    await _requestPhotoLibraryPermission();
  }

  /// Request camera permission
  Future<PermissionStatus> _requestCameraPermission() async {
    final status = await Permission.camera.status;

    if (status.isDenied) {
      return await Permission.camera.request();
    }

    return status;
  }

  /// Request photo library permission
  Future<PermissionStatus> _requestPhotoLibraryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.status;

      if (status.isDenied) {
        return await Permission.photos.request();
      }

      return status;
    } else {
      // Android uses storage permission
      final status = await Permission.storage.status;

      if (status.isDenied) {
        return await Permission.storage.request();
      }

      return status;
    }
  }

  /// Check if camera permission is granted
  Future<bool> isCameraPermissionGranted() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Check if photo library permission is granted
  Future<bool> isPhotoLibraryPermissionGranted() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.status;
      return status.isGranted || status.isLimited;
    } else {
      final status = await Permission.storage.status;
      return status.isGranted;
    }
  }

  /// Open app settings to manually grant permissions
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
