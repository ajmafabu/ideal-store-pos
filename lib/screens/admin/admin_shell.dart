import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_colors.dart';
import '../../services/update_service.dart';
import '../../config/providers.dart';
import '../../config/theme_provider.dart';
import '../shared/dashboard_screen.dart';
import '../shared/inventory_screen.dart';
import '../shared/sales_screen.dart';
import '../desktop/desktop_billing_screen.dart';
import '../desktop/desktop_purchase_screen.dart';
import 'purchase_screen.dart';
import 'expense_screen.dart';
import 'reports_screen.dart';
import 'staff_screen.dart';
import 'customer_screen.dart';
import 'supplier_screen.dart';
import 'accounts_screen.dart';
import 'shop_settings_screen.dart';
import 'gst_report_screen.dart';
import 'daily_report_screen.dart';
import 'factory_reset_screen.dart';
import 'returns_screen.dart';
import 'damaged_screen.dart';
import 'barcode_label_screen.dart';
import 'printer_setup_screen.dart';
import 'purchase_order_screen.dart';
import 'analytics_screen.dart';
import 'backup_screen.dart';
import 'gst_filing_screen.dart';
import 'slow_moving_screen.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> with SingleTickerProviderStateMixin {
  late AnimationController _fabAnimController;
  late Animation<double> _fabScaleAnimation;

  // Platform-aware screens: Desktop uses billing screen, Mobile uses sales screen
  late final List<Widget> _screens = [
    const DashboardScreen(),
    const InventoryScreen(),
    if (Platform.isWindows) const DesktopBillingScreen() else const SalesScreen(),
    if (Platform.isWindows) const DesktopPurchaseScreen() else const PurchaseScreen(),
    const ExpenseScreen(),
    const ReportsScreen(),
    const StaffScreen(),
    const CustomerScreen(),
    const SupplierScreen(),
    const AccountsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabScaleAnimation = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );
    _fabAnimController.forward();
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(currentTabProvider);

    if (Platform.isWindows) {
      return _buildDesktopLayout(currentIndex);
    }

    return _buildMobileLayout(currentIndex);
  }

  Widget _buildDesktopLayout(int currentIndex) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit App?'),
            content: const Text('Do you want to exit Ideal Store POS?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (shouldExit == true && context.mounted) exit(0);
      },
      child: Scaffold(
        body: Row(
          children: [
            // ── SIDEBAR (hidden on Billing & Purchase pages for full-screen access) ──
            if (currentIndex != 2 && currentIndex != 3)
            Container(
              width: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
              ),
              child: Column(
                children: [
                  // Logo
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: const Row(
                      children: [
                        Icon(Icons.store, color: Color(0xFF10B981), size: 28),
                        SizedBox(width: 10),
                        Text('IDEAL STORE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),

                  // Main nav
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        const _SidebarSection('MAIN'),
                        _SidebarItem(icon: Icons.dashboard_rounded, label: 'Dashboard', index: 0, currentIndex: currentIndex, onTap: _switchTab),
                        _SidebarItem(icon: Icons.point_of_sale, label: 'Billing', index: 2, currentIndex: currentIndex, onTap: _switchTab, highlight: true),
                        _SidebarItem(icon: Icons.inventory_2_rounded, label: 'Inventory', index: 1, currentIndex: currentIndex, onTap: _switchTab),
                        _SidebarItem(icon: Icons.shopping_cart_rounded, label: 'Purchases', index: 3, currentIndex: currentIndex, onTap: _switchTab),

                        const _SidebarSection('MANAGEMENT'),
                        _SidebarItem(icon: Icons.people_alt_rounded, label: 'Customers', index: 7, currentIndex: currentIndex, onTap: _switchTab),
                        _SidebarItem(icon: Icons.business_rounded, label: 'Suppliers', index: 8, currentIndex: currentIndex, onTap: _switchTab),
                        _SidebarItem(icon: Icons.people_rounded, label: 'Staff', index: 6, currentIndex: currentIndex, onTap: _switchTab),
                        _SidebarItem(icon: Icons.money_off_rounded, label: 'Expenses', index: 4, currentIndex: currentIndex, onTap: _switchTab),

                        const _SidebarSection('TOOLS'),
                        _SidebarItem(icon: Icons.replay_rounded, label: 'Returns', index: -5, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsScreen()))),
                        _SidebarItem(icon: Icons.broken_image_rounded, label: 'Damaged', index: -6, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const DamagedScreen()))),
                        _SidebarItem(icon: Icons.shopping_bag_rounded, label: 'Purchase Orders', index: -7, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseOrderScreen()))),
                        _SidebarItem(icon: Icons.qr_code_2_rounded, label: 'Barcode Labels', index: -8, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const BarcodeLabelScreen()))),
                        _SidebarItem(icon: Icons.trending_down_rounded, label: 'Slow Moving', index: -14, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const SlowMovingScreen()))),
                        _SidebarItem(icon: Icons.print_rounded, label: 'Printer Setup', index: -9, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSetupScreen()))),
                        _SidebarItem(icon: Icons.backup_rounded, label: 'Backup & Restore', index: -12, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()))),
                        _SidebarItem(icon: Icons.receipt_long_rounded, label: 'GST Filing Export', index: -13, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const GstFilingScreen()))),
                      ],
                    ),
                  ),

                  // Bottom actions
                  const Divider(color: Colors.white12, height: 1),
                  // Sync Status Indicator
                  Consumer(
                    builder: (context, ref, _) {
                      final syncStatus = ref.watch(syncStatusProvider);
                      return syncStatus.when(
                        data: (status) {
                          if (!status.hasPending && status.isConnected && status.lastSyncError == null) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: status.lastSyncError != null
                                  ? Colors.red.withValues(alpha: 0.15)
                                  : status.isConnected
                                      ? Colors.orange.withValues(alpha: 0.1)
                                      : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: status.lastSyncError != null
                                    ? Colors.red.withValues(alpha: 0.5)
                                    : status.isConnected
                                        ? Colors.orange.withValues(alpha: 0.3)
                                        : Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      status.lastSyncError != null
                                          ? Icons.error_outline_rounded
                                          : status.isConnected
                                              ? Icons.cloud_upload_rounded
                                              : Icons.cloud_off_rounded,
                                      size: 16,
                                      color: status.lastSyncError != null
                                          ? Colors.red
                                          : status.isConnected
                                              ? Colors.orange
                                              : Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            status.lastSyncError != null
                                                ? 'Sync Failed'
                                                : status.isConnected
                                                    ? 'Syncing...'
                                                    : 'Offline',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: status.lastSyncError != null
                                                  ? Colors.red
                                                  : status.isConnected
                                                      ? Colors.orange
                                                      : Colors.red,
                                            ),
                                          ),
                                          if (status.hasPending)
                                            Text(
                                              '${status.totalPending} pending',
                                              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5)),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (status.hasPending)
                                      GestureDetector(
                                        onTap: () async {
                                          final offlineService = ref.read(offlineServiceProvider);
                                          await offlineService.forceSync();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(Icons.refresh_rounded, size: 14, color: Colors.white70),
                                        ),
                                      ),
                                    if (status.hasPending) ...[
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Clear Pending Sales?'),
                                              content: Text('This will remove ${status.totalPending} pending items from the queue. They will NOT be saved to the server.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                  child: const Text('Clear'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true) {
                                            final offlineService = ref.read(offlineServiceProvider);
                                            await offlineService.clearAllPending();
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (status.lastSyncError != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    status.lastSyncError!.length > 100
                                        ? '${status.lastSyncError!.substring(0, 100)}...'
                                        : status.lastSyncError!,
                                    style: TextStyle(fontSize: 9, color: Colors.red.withValues(alpha: 0.7)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                    },
                  ),
                  _SidebarItem(icon: Icons.store_rounded, label: 'Shop Settings', index: -10, currentIndex: currentIndex, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopSettingsScreen()))),
                  _SidebarItem(icon: Icons.logout_rounded, label: 'Sign Out', index: -11, currentIndex: currentIndex, onTap: (_) => _confirmSignOut()),
                ],
              ),
            ),

            // ── MAIN CONTENT ──
            Expanded(child: _screens[currentIndex]),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(int currentIndex) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit App?'),
            content: const Text('Do you want to exit Ideal Store POS?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (shouldExit == true && context.mounted) {
          if (Platform.isAndroid) {
            SystemNavigator.pop();
          } else {
            exit(0);
          }
        }
      },
      child: Scaffold(
      body: _screens[currentIndex],
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: currentIndex == 2 ? AppColors.fabGradient : AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: (currentIndex == 2 ? const Color(0xFFf5576c) : const Color(0xFF667eea)).withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: () {
              setState(() => ref.read(currentTabProvider.notifier).setTab(2));
              _fabAnimController.reset();
              _fabAnimController.forward();
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: const Icon(
              Icons.point_of_sale,
              size: 28,
              color: Colors.white,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sync status bar (only shows when there's pending data)
          Consumer(
            builder: (context, ref, _) {
              final syncStatus = ref.watch(syncStatusProvider);
              return syncStatus.when(
                data: (status) {
                  if (!status.hasPending && status.isConnected && status.lastSyncError == null) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: status.hasPending
                        ? () async {
                            final offlineService = ref.read(offlineServiceProvider);
                            await offlineService.forceSync();
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      color: status.lastSyncError != null
                          ? Colors.red.withValues(alpha: 0.15)
                          : status.isConnected
                              ? Colors.orange.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            status.lastSyncError != null
                                ? Icons.error_outline_rounded
                                : status.isConnected
                                    ? Icons.cloud_upload_rounded
                                    : Icons.cloud_off_rounded,
                            size: 14,
                            color: status.lastSyncError != null
                                ? Colors.red
                                : status.isConnected
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              status.lastSyncError != null
                                  ? 'Sync failed — tap to retry'
                                  : status.isConnected
                                      ? (status.hasPending ? 'Syncing ${status.totalPending} items...' : 'Online')
                                      : 'Offline — ${status.totalPending} items pending',
                              style: TextStyle(
                                fontSize: 11,
                                color: status.lastSyncError != null
                                    ? Colors.red
                                    : status.isConnected
                                        ? Colors.orange
                                        : Colors.red,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (status.hasPending)
                            const Icon(Icons.refresh_rounded, size: 14, color: Colors.orange),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
          BottomAppBar(
            shape: const CircularNotchedRectangle(),
            notchMargin: 8,
            color: Theme.of(context).bottomAppBarTheme.color,
            elevation: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Home',
                  screenIndex: 0,
                  color: const Color(0xFF667eea),
                  currentIndex: currentIndex,
                ),
                _NavItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Stock',
                  screenIndex: 1,
                  color: const Color(0xFF8E2DE2),
                  currentIndex: currentIndex,
                ),
                const SizedBox(width: 48),
                _NavItem(
                  icon: Icons.shopping_cart_rounded,
                  label: 'Purchase',
                  screenIndex: 3,
                  color: const Color(0xFF11998e),
                  currentIndex: currentIndex,
                ),
                _NavItem(
                  icon: Icons.more_horiz_rounded,
                  label: 'More',
                  screenIndex: -1,
                  color: const Color(0xFF764ba2),
                  currentIndex: currentIndex,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _NavItem({required IconData icon, required String label, required int screenIndex, required Color color, required int currentIndex}) {
    final isSelected = currentIndex == screenIndex;

    return GestureDetector(
      onTap: () {
        if (screenIndex == -1) {
          _showMoreMenu();
        } else {
          setState(() => ref.read(currentTabProvider.notifier).setTab(screenIndex));
          _fabAnimController.reset();
          _fabAnimController.forward();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? color : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? color : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
              _MoreMenuItem(
                icon: Icons.people_alt_rounded,
                title: 'Customers',
                color: const Color(0xFF667eea),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => ref.read(currentTabProvider.notifier).setTab(7));
                },
              ),
              _MoreMenuItem(
                icon: Icons.business_rounded,
                title: 'Suppliers',
                color: const Color(0xFF11998e),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => ref.read(currentTabProvider.notifier).setTab(8));
                },
              ),
              _MoreMenuItem(
                icon: Icons.receipt_long_rounded,
                title: 'Reports',
                color: const Color(0xFF8E2DE2),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => ref.read(currentTabProvider.notifier).setTab(5));
                },
              ),
              _MoreMenuItem(
                icon: Icons.receipt_rounded,
                title: 'GST Reports',
                color: const Color(0xFF00897B),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const GSTReportScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.lock_clock_rounded,
                title: 'Daily Report (Z-Report)',
                color: const Color(0xFFE91E63),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DailyReportScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.people_rounded,
                title: 'Staff',
                color: const Color(0xFF764ba2),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => ref.read(currentTabProvider.notifier).setTab(6));
                },
              ),
              _MoreMenuItem(
                icon: Icons.money_off_rounded,
                title: 'Expenses',
                color: const Color(0xFFeb3349),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => ref.read(currentTabProvider.notifier).setTab(4));
                },
              ),
              _MoreMenuItem(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Accounts',
                color: const Color(0xFF11998e),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => ref.read(currentTabProvider.notifier).setTab(9));
                },
              ),
              _MoreMenuItem(
                icon: Icons.store_rounded,
                title: 'Shop Settings',
                color: const Color(0xFF764ba2),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopSettingsScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.qr_code_2_rounded,
                title: 'Barcode Labels',
                color: const Color(0xFF00897B),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BarcodeLabelScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.trending_down_rounded,
                title: 'Slow Moving Stock',
                color: const Color(0xFFE91E63),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SlowMovingScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.print_rounded,
                title: 'Printer Setup',
                color: const Color(0xFF5C6BC0),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSetupScreen()));
                },
              ),
              const SizedBox(height: 8),
              _MoreMenuItem(
                icon: Icons.replay_rounded,
                title: 'Returns',
                color: const Color(0xFFFF9800),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.broken_image_rounded,
                title: 'Damaged Products',
                color: const Color(0xFFf44336),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DamagedScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.shopping_bag_rounded,
                title: 'Purchase Orders',
                color: const Color(0xFF11998e),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseOrderScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.analytics_rounded,
                title: 'Analytics',
                color: const Color(0xFF667eea),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.backup_rounded,
                title: 'Backup & Restore',
                color: const Color(0xFF11998e),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()));
                },
              ),
              _MoreMenuItem(
                icon: Icons.receipt_long_rounded,
                title: 'GST Filing Export',
                color: const Color(0xFF00897B),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const GstFilingScreen()));
                },
              ),
              const SizedBox(height: 8),
              _MoreMenuItem(
                icon: Icons.system_update_rounded,
                title: 'Check for Updates',
                color: const Color(0xFF2196F3),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final service = UpdateService();
                    final update = await service.checkForUpdate();
                    if (!context.mounted) return;

                    if (update == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You are on the latest version')),
                      );
                      return;
                    }

                    // Show update dialog
                    final shouldUpdate = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: Row(
                          children: [
                            const Icon(Icons.system_update, color: Colors.blue),
                            const SizedBox(width: 8),
                            const Text('Update Available'),
                          ],
                        ),
                        content: Text(
                          'Version ${update.latestVersion} is available.\n\nYou are on version ${update.currentVersion}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx, false),
                            child: const Text('Later'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dctx, true),
                            child: const Text('Update Now'),
                          ),
                        ],
                      ),
                    );

                    if (shouldUpdate == true && context.mounted) {
                      // Show progress dialog
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (dctx) => _UpdateProgressDialog(update: update),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Update check failed: $e')),
                      );
                    }
                  }
                },
              ),
              _ThemeMenuItem(),
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: _MoreMenuItem(
                  icon: Icons.lock_outline_rounded,
                  title: 'Change Password',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showChangePassword();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: _MoreMenuItem(
                  icon: Icons.delete_forever_rounded,
                  title: 'Factory Reset',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FactoryResetScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: _MoreMenuItem(
                  icon: Icons.logout_rounded,
                  title: 'Sign Out',
                  color: Colors.red,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Sign Out'),
                        content: const Text('Are you sure you want to sign out?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      ref.invalidate(profileProvider);
                      await ref.read(authServiceProvider).signOut();
                      if (context.mounted) context.go('/login');
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChangePassword() {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('Change Password'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentController,
                  obscureText: obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(obscureCurrent ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_reset),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      final current = currentController.text.trim();
                      final newPass = newController.text.trim();
                      final confirm = confirmController.text.trim();

                      if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Fill all fields')),
                        );
                        return;
                      }
                      if (newPass.length < 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('New password must be at least 6 characters')),
                        );
                        return;
                      }
                      if (newPass != confirm) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('New passwords do not match')),
                        );
                        return;
                      }

                      setDialogState(() => loading = true);

                      try {
                        // Re-authenticate with current password
                        final email = Supabase.instance.client.auth.currentUser?.email;
                        if (email == null) throw Exception('Not logged in');

                        await Supabase.instance.client.auth.signInWithPassword(
                          email: email,
                          password: current,
                        );

                        // Update password
                        await Supabase.instance.client.auth.updateUser(
                          UserAttributes(password: newPass),
                        );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password changed successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => loading = false);
                        if (ctx.mounted) {
                          final msg = e.toString().contains('Invalid login credentials')
                              ? 'Current password is incorrect'
                              : 'Error: $e';
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(msg), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  void _switchTab(int index) {
    setState(() => ref.read(currentTabProvider.notifier).setTab(index));
    _fabAnimController.reset();
    _fabAnimController.forward();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.invalidate(profileProvider);
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) context.go('/login');
    }
  }
}

class _SidebarSection extends StatelessWidget {
  final String title;
  const _SidebarSection(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 1.2),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final void Function(int) onTap;
  final bool highlight;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = currentIndex == index;
    final color = highlight ? const Color(0xFF10B981) : const Color(0xFF667eea);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isSelected ? color : Colors.white.withValues(alpha: 0.6)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? color : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                if (highlight && index == 2)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('POS', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _MoreMenuItem({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
      onTap: onTap,
    );
  }
}

class _ThemeMenuItem extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.dark_mode_rounded, color: Colors.indigo),
        ),
        title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          currentMode == ThemeMode.light
              ? 'Light'
              : currentMode == ThemeMode.dark
                  ? 'Dark'
                  : 'System',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        children: [
          ListTile(
            leading: Icon(
              currentMode == ThemeMode.light ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: currentMode == ThemeMode.light ? Colors.indigo : null,
            ),
            title: const Text('Light'),
            onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeMode.light),
          ),
          ListTile(
            leading: Icon(
              currentMode == ThemeMode.dark ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: currentMode == ThemeMode.dark ? Colors.indigo : null,
            ),
            title: const Text('Dark'),
            onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeMode.dark),
          ),
          ListTile(
            leading: Icon(
              currentMode == ThemeMode.system ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: currentMode == ThemeMode.system ? Colors.indigo : null,
            ),
            title: const Text('System'),
            onTap: () => ref.read(themeProvider.notifier).setThemeMode(ThemeMode.system),
          ),
        ],
      ),
    );
  }
}

class _UpdateProgressDialog extends StatefulWidget {
  final UpdateInfo update;
  const _UpdateProgressDialog({required this.update});

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double _progress = 0;
  String _status = 'Downloading...';

  @override
  void initState() {
    super.initState();
    _startUpdate();
  }

  Future<void> _startUpdate() async {
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
          _status = 'Installing... Restarting...';
          _progress = 1;
        });
        await Future.delayed(const Duration(seconds: 2));
        await service.installUpdate(extractDir);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Failed: $e');
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Updating...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress > 0 && _progress < 1 ? _progress : null),
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(fontSize: 13)),
          if (_progress > 0 && _progress < 1)
            Text('${(_progress * 100).toInt()}%', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }
}
