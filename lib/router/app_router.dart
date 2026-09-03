import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/auth/login_screen.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/staff/staff_shell.dart';
import '../screens/customer/customer_portal_screen.dart';
import '../config/providers.dart';
import '../services/version_check_service.dart';
import '../utils/logger.dart';

bool _needsUpdate = false;
String? _minVersion;

final routerNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authServiceProvider);

  return GoRouter(
    navigatorKey: routerNavigatorKey,
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(auth.authStateChanges),
    redirect: (context, state) async {
      final user = auth.currentUser;
      final path = state.matchedLocation;

      // Allow public customer portal access
      if (path.startsWith('/customer/')) return null;

      // Version check (only once per app session) — skip on Windows (handled by UpdateService)
      if (!_needsUpdate && user != null && path != '/login' && !Platform.isWindows) {
        try {
          final needsUpdate = await VersionCheckService().checkForUpdate();
          if (needsUpdate) {
            _needsUpdate = true;
            _minVersion = await VersionCheckService().getMinVersion();
            if (context.mounted) {
              _showUpdateDialog(context);
            }
            return null;
          }
        } catch (e) {
          // Don't block app if version check fails
        }
      }

      // Force update blocking
      if (_needsUpdate && path != '/login') {
        return null;
      }

      if (user == null) {
        return path == '/login' ? null : '/login';
      }

      if (path == '/login') {
        try {
          final profile = await auth.getCurrentProfile();
          if (profile != null) {
            return profile.isAdmin ? '/admin' : '/staff';
          }
        } catch (e) {
          Logger.error('Router redirect', e);
        }
        return null;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminShell(),
      ),
      GoRoute(
        path: '/staff',
        builder: (context, state) => const StaffShell(),
      ),
      GoRoute(
        path: '/customer/:customerId',
        builder: (context, state) {
          final customerId = state.pathParameters['customerId'] ?? '';
          return CustomerPortalScreen(customerId: customerId);
        },
      ),
    ],
  );
});

void _showUpdateDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_rounded, size: 48, color: Color(0xFF667eea)),
        title: const Text('Update Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'A new version of Ideal Store POS is available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (_minVersion != null) ...[
              const SizedBox(height: 8),
              Text(
                'Required: v$_minVersion',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final uri = Uri.parse('market://details?id=com.idealstore.pos');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667eea),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Update Now'),
            ),
          ),
        ],
      ),
    ),
  );
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
