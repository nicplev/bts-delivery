import 'package:flutter/material.dart';

import '../app/theme/app_tokens.dart';

class NotificationUtils {
  /// Show a toast-style notification (SnackBar)
  static void showToast(
    BuildContext context,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        isError ? scheme.onErrorContainer : AppTone.yellow.inkFor(context);

    // Clear any existing snackbars
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: foreground)),
        backgroundColor:
            isError ? scheme.errorContainer : AppTone.yellow.tintFor(context),
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
      isError: false,
      duration: const Duration(seconds: 4),
    );
  }

  /// Show a success notification
  static void showSuccess(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message,
            style: TextStyle(color: AppTone.green.inkFor(context))),
        backgroundColor: AppTone.green.tintFor(context),
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
