import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../providers/offline_delivery_providers.dart';
import '../services/offline/offline_storage_service.dart';

class BTSDeliveryApp extends ConsumerWidget {
  const BTSDeliveryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offlineStorageInit = ref.watch(offlineStorageInitProvider);

    return offlineStorageInit.when(
      data: (_) {
        ref.watch(evidenceUploadWorkerProvider);
        final router = ref.watch(appRouterProvider);

        return MaterialApp.router(
          title: 'BTS Delivery App',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        );
      },
      loading: () => MaterialApp(
        title: 'BTS Delivery App',
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Initializing app...'),
              ],
            ),
          ),
        ),
      ),
      error: (error, stack) => MaterialApp(
        title: 'BTS Delivery App',
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Initialization failed: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(offlineStorageInitProvider);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
