import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_theme.dart';
import 'config/hive_adapter.dart';
import 'config/providers.dart';
import 'config/supabase_config.dart';
import 'config/theme_provider.dart';
import 'router/app_router.dart';
import 'services/offline_service.dart';
import 'services/connectivity_service.dart';
import 'services/update_service.dart';
import 'utils/logger.dart';

BuildContext? _navigatorContext;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    Logger.error('Flutter Error', details.exception, details.stack);
  };

  runZonedGuarded(
    () async {
      await Hive.initFlutter();
      await HiveAdapter.init();

      final offlineService = OfflineService();
      await offlineService.init();

      final connectivityService = ConnectivityService();
      await connectivityService.init();

      if (!SupabaseConfig.isConfigured) {
        runApp(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Text(
                    'Supabase not configured.\n\nRun with:\nflutter run --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_ANON_KEY=your_key',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        );
        return;
      }

      // Initialize Supabase - continue even if offline, with timeout
      try {
        await Supabase.initialize(
          url: SupabaseConfig.supabaseUrl,
          publishableKey: SupabaseConfig.supabaseAnonKey,
        ).timeout(const Duration(seconds: 15), onTimeout: () {
          Logger.warning('Supabase init timed out after 15s');
          return Supabase.instance;
        });
      } catch (e) {
        Logger.warning('Supabase init failed (possibly offline): $e');
      }

      try {
        await [
          Permission.bluetooth,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request().timeout(const Duration(seconds: 5));
      } catch (e) {
        Logger.warning('Failed to request Bluetooth/location permissions: $e');
      }

      // Sync on startup if online
      try {
        if (await offlineService.isOnline()) {
          await offlineService.syncPendingSales();
        }
      } catch (e) {
        Logger.warning('Failed to sync offline sales on startup: $e');
      }

      // Auto-sync when connectivity is restored
      final connectivitySubscription =
          connectivityService.connectionStream.listen((isConnected) {
        if (isConnected) {
          Logger.info('Connectivity restored - syncing pending sales');
          offlineService
              .syncPendingSales()
              .then((_) {
                Logger.info('Auto-sync completed');
              })
              .catchError((e) {
                Logger.error('Auto-sync failed', e);
              });
        }
      });

      // Periodic retry: sync every 30s if pending items exist
      final syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        final hasPending = offlineService.pendingCount > 0 ||
            offlineService.pendingOpsCount > 0 ||
            offlineService.pendingWritesCount > 0;
        if (hasPending) {
          try {
            if (await offlineService.isOnline()) {
              await offlineService.syncPendingSales();
            }
          } catch (e) {
            Logger.warning('Periodic sync failed: $e');
          }
        }
      });

      runApp(const ProviderScope(child: MyApp()));

      // Auto-update check — 7s after runApp to ensure navigator is ready
      _scheduleUpdateCheck();
    },
    (error, stack) {
      Logger.error('Uncaught Error', error, stack);
    },
  );
}

void _scheduleUpdateCheck() {
  Timer(const Duration(seconds: 7), () async {
    final logFile = File('${Directory.systemTemp.path}\\update_debug.log');
    try {
      await logFile.writeAsString(
          '=== Update Check v1.0.24 ===\nTime: ${DateTime.now()}\n');

      final updateService = UpdateService();
      final update = await updateService.checkForUpdate();

      if (update != null) {
        await logFile.writeAsString(
            'UPDATE FOUND: ${update.currentVersion} → ${update.latestVersion}\n'
            'URL: ${update.downloadUrl}\n',
            mode: FileMode.append);

        if (_navigatorContext != null) {
          await logFile.writeAsString('Navigator context found, showing dialog via Overlay\n', mode: FileMode.append);
          final overlay = Overlay.of(_navigatorContext!);
          late OverlayEntry entry;
          entry = OverlayEntry(
            builder: (_) => _UpdateDialog(
              update: update,
              onDismiss: () => entry.remove(),
            ),
          );
          overlay.insert(entry);
        } else {
          await logFile.writeAsString('ERROR: _navigatorContext is null\n', mode: FileMode.append);
          print('[UPDATE] ERROR: _navigatorContext is null');
        }
      } else {
        await logFile.writeAsString('No update available\n', mode: FileMode.append);
        print('[UPDATE] App is up to date');
      }
    } catch (e, st) {
      print('[UPDATE] Update check failed: $e');
      try {
        logFile.writeAsStringSync('ERROR: $e\n$st\n', mode: FileMode.append);
      } catch (_) {}
    }
  });
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeChannelProvider);

    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Ideal Store POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Capture context from INSIDE MaterialApp (has Navigator)
        _navigatorContext = context;
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo update;
  final VoidCallback? onDismiss;
  const _UpdateDialog({required this.update, this.onDismiss});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  String _status = 'Preparing...';
  bool _downloading = false;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _status = 'Downloading...';
    });

    try {
      final service = UpdateService();
      final extractDir = await service.downloadAndInstall(
        widget.update,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (mounted) {
        setState(() {
          _status = 'Installing... Restarting app...';
          _progress = 1;
        });
        await Future.delayed(const Duration(seconds: 2));
        await service.installUpdate(extractDir);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _status = 'Failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update, color: Colors.blue),
          const SizedBox(width: 8),
          const Text('Update Available'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${widget.update.latestVersion} is available.'),
          const SizedBox(height: 4),
          Text(
            'You are on version ${widget.update.currentVersion}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          if (widget.update.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.update.releaseNotes,
                style: const TextStyle(fontSize: 12),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress > 0 && _progress < 1 ? _progress : null),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () {
              widget.onDismiss?.call();
            },
            child: const Text('Later'),
          ),
        if (!_downloading)
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Update Now'),
          ),
      ],
    );
  }
}
