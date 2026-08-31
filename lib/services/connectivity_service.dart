import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/logger.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  bool _isConnected = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool get isConnected => _isConnected;
  Stream<bool> get connectionStream => _connectionStatusController.stream;

  Future<void> init() async {
    // Check initial connectivity
    try {
      final results = await _connectivity.checkConnectivity();
      _isConnected = results.any((r) => r != ConnectivityResult.none);
      _connectionStatusController.add(_isConnected);
    } catch (e) {
      Logger.error('ConnectivityService.init', e);
      _isConnected = false;
    }

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasConnected = _isConnected;
      _isConnected = results.any((r) => r != ConnectivityResult.none);

      if (wasConnected != _isConnected) {
        Logger.info(
          'Connectivity changed: ${_isConnected ? "ONLINE" : "OFFLINE"}',
        );
        _connectionStatusController.add(_isConnected);
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _connectionStatusController.close();
  }
}
