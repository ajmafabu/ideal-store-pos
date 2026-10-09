import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/providers.dart';
import '../desktop/desktop_billing_screen.dart';
import '../shared/dashboard_screen.dart';
import '../shared/inventory_screen.dart';
import '../shared/sales_screen.dart';

/// Staff get the same billing as admins on Windows (the keyboard POS),
/// without the admin-only screens (#25). Layout follows the window width
/// (#26): a side rail from 600 px, a bottom bar below that.
class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  int _currentIndex = Platform.isWindows ? 2 : 0;

  late final List<Widget> _screens = [
    const DashboardScreen(),
    const InventoryScreen(),
    if (Platform.isWindows) const DesktopBillingScreen() else const SalesScreen(),
  ];

  static const _destinations = [
    (icon: Icons.dashboard_rounded, label: 'Dashboard'),
    (icon: Icons.inventory_2_rounded, label: 'Inventory'),
    (icon: Icons.point_of_sale, label: 'Billing'),
  ];

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: Color(0xFFC62828))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.invalidate(profileProvider);
    await ref.read(authServiceProvider).signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final body = _screens[_currentIndex];
        if (!wide) {
          return Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) => setState(() => _currentIndex = i),
              destinations: [
                for (final d in _destinations) NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _currentIndex,
                onDestinationSelected: (i) => setState(() => _currentIndex = i),
                labelType: NavigationRailLabelType.all,
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IconButton(
                        tooltip: 'Sign out',
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: _signOut,
                      ),
                    ),
                  ),
                ),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
