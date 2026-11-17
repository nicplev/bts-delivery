import 'package:flutter/material.dart';

import '../app/theme/app_tokens.dart';

/// Floating snackbars: neutral ink surface for information and success, the
/// pale amber tint for warnings, the error container for errors.
class NotificationUtils {
  /// Show a toast-style notification (SnackBar)
  static void showToast(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final colors = AppPalette.of(context);
    // Null keeps the theme's neutral ink snackbar.
    final Color? foreground = isError
        ? colors.error
        : isWarning
            ? colors.warningInk
            : null;
    final Color? background = isError
        ? colors.errorContainer
        : isWarning
            ? colors.warningTint
            : null;

    // Clear any existing snackbars
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: foreground == null
              ? null
              : TextStyle(
                  color: foreground,
                  fontWeight: isWarning ? FontWeight.w600 : null,
                ),
        ),
        backgroundColor: background,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: foreground,
          onPressed: () {
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Show a sign-off cleared notification
  static void showSignOffClearedNotification(BuildContext context) {
    showToast(
      context,
      'Sign-off cleared due to data changes',
      isWarning: true,
      duration: const Duration(seconds: 4),
    );
  }

  /// Show a success notification
  static void showSuccess(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show an error notification
  static void showError(BuildContext context, String message) {
    showToast(context, message, isError: true);
  }
}
