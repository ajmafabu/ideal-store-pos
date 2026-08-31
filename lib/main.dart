import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config/app_theme.dart';
import 'config/hive_adapter.dart';
import 'config/providers.dart';
import 'config/supabase_config.dart';
import 'config/theme_provider.dart';
import 'router/app_router.dart';
import 'services/offline_service.dart';
import 'services/connectivity_service.dart';
import 'utils/logger.dart';

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

      // Initialize auto-updater (Windows only, after 5s delay)
      Future.delayed(const Duration(seconds: 5), () {
        _checkForUpdates();
      });

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
    },
    (error, stack) {
      Logger.error('Uncaught Error', error, stack);
    },
  );
}

Future<void> _checkForUpdates() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;

    final response = await http.get(
      Uri.parse('https://api.github.com/repos/ajmafabu/ideal-store-pos/releases/latest'),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return;

    final release = json.decode(response.body);
    final tagName = release['tag_name'] ?? '';
    final latestVersion = tagName.replaceFirst('v', '');
    final downloadUrl = (release['assets'] as List?)?.where(
      (a) => a['name']?.toString().endsWith('.zip') == true,
    ).toList();

    if (latestVersion.isNotEmpty &&
        latestVersion != currentVersion &&
        downloadUrl != null &&
        downloadUrl.isNotEmpty) {
      final url = downloadUrl.first['browser_download_url'] as String;
      Logger.info('Update available: $latestVersion (current: $currentVersion)');
      _pendingUpdate = (currentVersion, latestVersion, url);
    }
  } catch (e) {
    Logger.warning('Update check failed: $e');
  }
}

(String current, String latest, String url)? _pendingUpdate;

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeChannelProvider);

    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    // Show update dialog if pending
    if (_pendingUpdate != null) {
      final (current, latest, url) = _pendingUpdate!;
      _pendingUpdate = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Update Available'),
            content: Text('Version $latest is available.\n\nYou are on version $current.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () {
                  launchUrl(Uri.parse(url));
                  Navigator.pop(ctx);
                },
                child: const Text('Download'),
              ),
            ],
          ),
        );
      });
    }

    return MaterialApp.router(
      title: 'Ideal Store POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
