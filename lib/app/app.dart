import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../providers/offline_delivery_providers.dart';
import '../providers/saved_edit_providers.dart';
import '../providers/offline_media_providers.dart';
import '../services/offline/offline_storage_service.dart';

class BTSDeliveryApp extends ConsumerWidget {
  const BTSDeliveryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAnimationStyle =
        MediaQuery.maybeDisableAnimationsOf(context) == true
            ? AnimationStyle.noAnimation
            : null;
    final offlineStorageInit = ref.watch(offlineStorageInitProvider);

    return offlineStorageInit.when(
      data: (_) {
        ref.watch(evidenceUploadWorkerProvider);
        ref.watch(savedEditLifecycleProvider);
        ref.watch(offlineMediaWorkerProvider);
        final router = ref.watch(appRouterProvider);

        return MaterialApp.router(
          title: 'BTS Delivery App',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          highContrastTheme: AppTheme.highContrastLightTheme,
          highContrastDarkTheme: AppTheme.highContrastDarkTheme,
          themeAnimationStyle: themeAnimationStyle,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        );
      },
      loading: () => MaterialApp(
        title: 'BTS Delivery App',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        highContrastTheme: AppTheme.highContrastLightTheme,
        highContrastDarkTheme: AppTheme.highContrastDarkTheme,
        themeAnimationStyle: themeAnimationStyle,
        home: const _StartupScreen(
          icon: CircularProgressIndicator(),
          message: 'Initializing app...',
        ),
      ),
      error: (error, stack) => MaterialApp(
        title: 'BTS Delivery App',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        highContrastTheme: AppTheme.highContrastLightTheme,
        highContrastDarkTheme: AppTheme.highContrastDarkTheme,
        themeAnimationStyle: themeAnimationStyle,
        home: _StartupScreen(
          icon: const Icon(Icons.error_outline, size: 48),
          message: 'Initialization failed: $error',
          onRetry: () => ref.invalidate(offlineStorageInitProvider),
        ),
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final Widget icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
