import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectivityStatus {
  online,
  offline,
  checking,
}

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final _statusController = StreamController<ConnectivityStatus>.broadcast();

  Stream<ConnectivityStatus> get statusStream => _statusController.stream;
  ConnectivityStatus _currentStatus = ConnectivityStatus.checking;
  ConnectivityStatus get currentStatus => _currentStatus;

  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _disposed = false;

  ConnectivityService() {
    _initialize();
  }

  void _initialize() {
    // Check initial connectivity
    checkConnectivity();

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) {
        _updateConnectionStatus(result);
      },
    );
  }

  Future<void> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
    } catch (e) {
      _updateStatus(ConnectivityStatus.offline);
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    // Check if the result indicates a connection
    final hasConnection = result != ConnectivityResult.none &&
        result != ConnectivityResult.bluetooth;

    _updateStatus(
        hasConnection ? ConnectivityStatus.online : ConnectivityStatus.offline);
  }

  void _updateStatus(ConnectivityStatus status) {
    if (_disposed) return;
    _currentStatus = status;
    _statusController.add(status);
  }

  bool get isOnline => _currentStatus == ConnectivityStatus.online;
  bool get isOffline => _currentStatus == ConnectivityStatus.offline;

  Future<bool> hasInternetConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none &&
          result != ConnectivityResult.bluetooth;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isWifiConnected() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result == ConnectivityResult.wifi;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _connectivitySubscription?.cancel();
    _statusController.close();
  }
}

// Provider for connectivity service
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Provider for connectivity status stream
final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return Stream.multi((sink) {
    final subscription =
        service.statusStream.listen(sink.add, onDone: sink.close);
    sink.onCancel = subscription.cancel;
    sink.add(service.currentStatus);
  });
});

// Provider for current connectivity status
final isOnlineProvider = Provider<bool>((ref) {
  final statusAsync = ref.watch(connectivityStatusProvider);
  return statusAsync.when(
    data: (status) => status == ConnectivityStatus.online,
    loading: () => false,
    error: (_, __) => false,
  );
});
