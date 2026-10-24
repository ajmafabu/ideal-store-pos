import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/providers.dart';
import '../../models/product.dart';
import '../../utils/app_timezone.dart';
import '../../utils/paged_query.dart';
import '../../utils/product_profit.dart';
import '../../utils/qty_format.dart';
import '../../widgets/my_account_sheet.dart';
import '../admin/all_low_stock_screen.dart';
import '../admin/all_profitable_products_screen.dart';
import '../admin/profit_details_screen.dart';
import '../admin/stock_check_screen.dart';
import '../admin/stock_health_screen.dart';
import 'dashboard_widgets/expiring_products_section.dart';

/// The phone Home screen (23 Oct 2026, design "Home D"): a light ocean-blue
/// top with today's sales and the week, coloured cards below, and the day's
/// jobs. Windows keeps the old dashboard.
class PhoneHome extends ConsumerWidget {
  const PhoneHome({
    super.key,
    required this.onRefresh,
    required this.onSync,
    required this.onSignOut,
    required this.syncing,
    required this.pendingCount,
  });

  final Future<void> Function() onRefresh;
  final VoidCallback onSync;
  final VoidCallback onSignOut;
  final bool syncing;
  final int pendingCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(dashboardIsAdminProvider).value ?? false;
    final statusBar = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: _C.page,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              children: [
                _TopBand(onSync: onSync, onSignOut: onSignOut, syncing: syncing, pendingCount: pendingCount),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Tiles(isAdmin: isAdmin),
                      const SizedBox(height: 18),
                      _Jobs(isAdmin: isAdmin),
                      if (isAdmin) ...[
                        const SizedBox(height: 18),
                        const _WhereMoneyGoes(),
                        const SizedBox(height: 18),
                        const _TopEarners(),
                      ],
                      const SizedBox(height: 18),
                      const _RunningOut(),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
                const ExpiringProductsSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),
          // the page scrolls under the phone's status bar: keep it readable
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: statusBar,
            child: const ColoredBox(color: _C.band),
          ),
        ],
      ),
    );
  }
}

/// The design's colours.
class _C {
  static const page = Color(0xFFF4F8FB);
  static const band = Color(0xFFCFEAF7);
  static const navy = Color(0xFF0A3550);
  static const navyMuted = Color(0xFF3F6278);
  static const ocean = Color(0xFF0E7FB4);
  static const bar = Color(0xFF9DD1EA);
  static const down = Color(0xFFA3301C);
  static const muted = Color(0xFF5B626E);
  static const green = Color(0xFF0F7A4E);
  static const line = Color(0xFFDDE7EE);
}

String _inr(double v) => '₹${NumberFormat('#,##,##0', 'en_IN').format(v.round())}';

/// 125000 → 1.25L, 99000 → 99K: short enough to sit above a bar.
String _short(double v) {
  if (v >= 100000) {
    final l = (v / 100000).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '${l}L';
  }
  if (v >= 1000) return '${(v / 1000).round()}K';
  return v.round().toString();
}

// ── top: shop, today's sales, the week ──────────────────────────────────
class _TopBand extends ConsumerWidget {
  const _TopBand({required this.onSync, required this.onSignOut, required this.syncing, required this.pendingCount});
  final VoidCallback onSync;
  final VoidCallback onSignOut;
  final bool syncing;
  final int pendingCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final sales = ref.watch(todaySalesProvider).value ?? 0;
    final yesterday = ref.watch(yesterdaySalesProvider).value ?? 0;
    final bills = ref.watch(todayOrderCountProvider).value ?? 0;
    final shop = (profile?.shopName?.trim().isNotEmpty ?? false) ? profile!.shopName!.trim() : 'Ideal Store';
    final initials = shop
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final now = AppTimezone.nowIst();
    final trend = yesterday > 0 ? (sales - yesterday) / yesterday * 100 : null;

    return Container(
      decoration: const BoxDecoration(
        color: _C.band,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(18, MediaQuery.paddingOf(context).top + 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _C.ocean, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _C.navy),
                    ),
                    Text(
                      DateFormat('EEE d MMM · h:mm a').format(now),
                      style: const TextStyle(fontSize: 12, color: _C.navyMuted),
                    ),
                  ],
                ),
              ),
              _RoundButton(
                tooltip: pendingCount > 0 ? 'Send $pendingCount offline bills' : 'Refresh',
                onTap: onSync,
                badge: pendingCount > 0 ? '$pendingCount' : null,
                child: syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _C.navy),
                      )
                    : const Icon(Icons.sync_rounded, size: 20, color: _C.navy),
              ),
              const SizedBox(width: 6),
              _RoundButton(
                tooltip: 'My account',
                onTap: profile == null ? null : () => showMyAccountSheet(context, ref, profile),
                child: Text(
                  (profile?.name.isNotEmpty ?? false) ? profile!.name[0].toUpperCase() : 'U',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: _C.navy),
                ),
              ),
              const SizedBox(width: 6),
              _RoundButton(
                tooltip: 'Sign out',
                onTap: onSignOut,
                child: const Icon(Icons.logout_rounded, size: 20, color: _C.down),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            "TODAY'S SALES",
            style: TextStyle(fontSize: 13, color: _C.navyMuted, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          Text(
            _inr(sales),
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              height: 1,
              color: _C.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (trend != null) '${trend >= 0 ? '↑' : '↓'} ${trend.abs().toStringAsFixed(0)}% vs yesterday',
              '$bills bill${bills == 1 ? '' : 's'}',
            ].join(' · '),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: trend == null ? _C.navyMuted : (trend >= 0 ? _C.green : _C.down),
            ),
          ),
          const SizedBox(height: 18),
          const _WeekChart(),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.onTap, required this.child, this.badge});
  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: Color(0xFFA9D5EA))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                child,
                if (badge != null)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC2410C),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last seven days, each bar with its sales value on top.
class _WeekChart extends ConsumerWidget {
  const _WeekChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(weeklySalesProvider);
    return Container(
      height: 128,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: week.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, __) => const Center(
          child: Text('Could not load the week', style: TextStyle(color: _C.muted)),
        ),
        data: (days) {
          if (days.isEmpty) {
            return const Center(
              child: Text('No sales this week', style: TextStyle(color: _C.muted)),
            );
          }
          final totals = [for (final d in days) (d['total'] as num? ?? 0).toDouble()];
          final top = totals.reduce((a, b) => a > b ? a : b);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _short(totals[i]),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: i == days.length - 1 ? _C.ocean : _C.navy,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: top > 0 ? (totals[i] / top * 60).clamp(4, 60).toDouble() : 4,
                          decoration: BoxDecoration(
                            color: i == days.length - 1 ? _C.ocean : _C.bar,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          i == days.length - 1 ? 'Today' : (days[i]['day']?.toString() ?? ''),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            color: i == days.length - 1 ? _C.navy : _C.navyMuted,
                            fontWeight: i == days.length - 1 ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── coloured tiles ─────────────────────────────────────────────────────
class _Tiles extends ConsumerWidget {
  const _Tiles({required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(monthlyProfitProvider).value ?? const {};
    final stock = ref.watch(stockValueProvider).value ?? 0;
    final todayExp = ref.watch(todayExpensesProvider).value ?? 0;
    final days = ref.watch(weeklySalesProvider).value ?? const [];
    final bills = ref.watch(todayOrderCountProvider).value ?? 0;
    final weekTotal = days.fold<double>(0, (t, d) => t + (d['total'] as num? ?? 0).toDouble());
    Map<String, dynamic>? best;
    for (final d in days) {
      if (best == null || (d['total'] as num? ?? 0) > (best['total'] as num? ?? 0)) best = d;
    }
    final sales = month['sales'] ?? 0;
    final profit = month['profit'] ?? 0;
    final monthName = DateFormat('MMM').format(AppTimezone.nowIst());
    void open(int tab) => ref.read(currentTabProvider.notifier).setTab(tab);

    final weekTile = _Tile(
      color: const Color(0xFFEFEAFB),
      label: 'This week',
      value: _short(weekTotal) == '0' ? '₹0' : '₹${_short(weekTotal)}',
      note: best == null ? '' : 'best day ${best['day']} ₹${_short((best['total'] as num? ?? 0).toDouble())}',
    );

    final tiles = isAdmin
        ? [
            _Tile(
              color: const Color(0xFFE3F5EA),
              label: 'Profit · $monthName',
              value: _inr(profit),
              valueColor: profit >= 0 ? _C.green : _C.down,
              note: sales > 0 ? '${(profit / sales * 100).toStringAsFixed(1)}% of sales' : '',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfitDetailsScreen(initialPeriod: 'monthly')),
              ),
            ),
            _Tile(
              color: const Color(0xFFE4EEFD),
              label: 'Stock value',
              value: _inr(stock),
              note: 'at cost price',
              onTap: () => open(1),
            ),
            _Tile(
              color: const Color(0xFFFDEFE0),
              label: 'Expenses · $monthName',
              value: _inr(month['expenses'] ?? 0),
              note: '${_inr(todayExp)} today',
              onTap: () => open(4),
            ),
            weekTile,
          ]
        : [_Tile(color: const Color(0xFFE4EEFD), label: 'Bills today', value: '$bills', note: ''), weekTile];

    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.color,
    required this.label,
    required this.value,
    required this.note,
    this.valueColor,
    this.onTap,
  });
  final Color color;
  final String label;
  final String value;
  final String note;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: _C.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: valueColor ?? _C.navy),
                ),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _C.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── today's jobs ───────────────────────────────────────────────────────
class _Job {
  _Job(this.badge, this.title, this.help, this.action, this.onTap, this.bg, this.fg, {this.done = false, this.icon});
  final String badge;
  final IconData? icon;
  final String title;
  final String help;
  final String action;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;
  final bool done;
}

class _Jobs extends ConsumerWidget {
  const _Jobs({required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final pending = products.where((p) => !p.hasVariants && p.stock < -0.0005).length;
    final empty = products.where((p) => !p.hasVariants && !p.isHidden && p.stock.abs() < 0.0005).length;
    final todayExp = ref.watch(todayExpensesProvider).value ?? 0;
    void push(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    final jobs = [
      if (isAdmin)
        _Job(
          '$pending',
          'Enter pending purchases',
          pending == 0 ? 'Nothing sold ahead of its bill' : 'Sold before the bill was entered',
          'Start',
          () => push(const StockHealthScreen()),
          const Color(0xFFFFF4DE),
          const Color(0xFF6B3A00),
          done: pending == 0,
        ),
      if (isAdmin)
        _Job(
          '',
          'Count today’s products',
          'Short daily list · about 10 min',
          'Start',
          () => push(const StockCheckScreen()),
          const Color(0xFFE6EDFB),
          const Color(0xFF1A3E99),
          icon: Icons.fact_check_outlined,
        ),
      _Job(
        '$empty',
        'Reorder empty shelves',
        'Out of stock',
        'View',
        () => push(const AllLowStockScreen()),
        const Color(0xFFFDE8E6),
        const Color(0xFF8F1D14),
        done: empty == 0,
      ),
      if (isAdmin)
        _Job(
          _short(todayExp) == '0' ? '₹0' : '₹${_short(todayExp)}',
          'Record today’s expenses',
          todayExp > 0 ? '${_inr(todayExp)} entered today' : 'Nothing entered yet',
          'Add',
          () => ref.read(currentTabProvider.notifier).setTab(4),
          const Color(0xFFEEF0F3),
          _C.navy,
          done: todayExp > 0,
        ),
    ];
    final done = jobs.where((j) => j.done).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's jobs",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.navy),
                ),
              ),
              Text(
                '$done of ${jobs.length} done',
                style: const TextStyle(fontSize: 13, color: _C.muted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: const Color(0xFFEAF6FC), borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              for (var i = 0; i < jobs.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: _C.line),
                _JobRow(job: jobs[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});
  final _Job job;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: job.done ? const Color(0xFFE3F5EA) : job.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: job.done
                ? const Icon(Icons.check_rounded, color: _C.green)
                : job.icon != null
                ? Icon(job.icon, color: job.fg)
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      job.badge,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: job.fg),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: job.done ? _C.muted : _C.navy),
                ),
                const SizedBox(height: 1),
                Text(job.help, style: const TextStyle(fontSize: 12, color: _C.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: job.onTap,
            style: FilledButton.styleFrom(
              backgroundColor: _C.ocean,
              foregroundColor: Colors.white,
              minimumSize: const Size(64, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: Text(job.action),
          ),
        ],
      ),
    );
  }
}

// ── where ₹100 of sales goes (this month) ──────────────────────────────
class _WhereMoneyGoes extends ConsumerWidget {
  const _WhereMoneyGoes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(monthlyProfitProvider).value ?? const {};
    final sales = m['sales'] ?? 0;
    final cogs = m['cogs'] ?? 0;
    final expenses = m['expenses'] ?? 0;
    final profit = m['profit'] ?? 0;
    double per100(double v) => sales > 0 ? v / sales * 100 : 0;

    Widget row(String label, double v, Color color, {bool bold = false}) {
      final share = per100(v);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: _C.navy,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '₹${share.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: bold ? (v >= 0 ? _C.green : _C.down) : _C.navy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (share / 100).clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: Colors.white,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return _Card(
      color: const Color(0xFFE8F7F2),
      title: 'Where ₹100 of sales goes',
      action: DateFormat('MMMM').format(AppTimezone.nowIst()),
      onAction: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfitDetailsScreen(initialPeriod: 'monthly')),
      ),
      children: [
        row('Goods we bought', cogs, const Color(0xFF8C96A5)),
        row('Shop expenses', expenses, const Color(0xFFD9822B)),
        row('Profit', profit, _C.green, bold: true),
        const Divider(height: 12, color: _C.line),
        Row(
          children: [
            Expanded(
              child: Text('Sales ${_inr(sales)}', style: const TextStyle(fontSize: 13, color: _C.muted)),
            ),
            Text('Cost ${_inr(cogs)}', style: const TextStyle(fontSize: 13, color: _C.muted)),
          ],
        ),
      ],
    );
  }
}

// ── top earners this month ─────────────────────────────────────────────
/// Products with the most profit this month (decimals and returns
/// included), most first.
Future<List<Map<String, dynamic>>> loadMonthTopProfit() async {
  final client = Supabase.instance.client;
  final now = AppTimezone.nowIst();
  final start = DateTime.utc(now.year, now.month, 1).subtract(AppTimezone.localOffset);
  final end = DateTime.utc(now.year, now.month, now.day + 1).subtract(AppTimezone.localOffset);
  final salesRes = await fetchAllRows(
    () => client
        .from('sales')
        .select('items')
        .gte('created_at', start.toIso8601String())
        .lt('created_at', end.toIso8601String()),
  );
  final productsRes = await fetchAllRows(() => client.from('products').select('id, purchase_price'));
  final costMap = <String, double>{
    for (final p in productsRes) p['id'] as String: (p['purchase_price'] as num?)?.toDouble() ?? 0,
  };
  final returnsRes = await fetchReturnsBetween(start, end);
  return ProductProfit.compute(sales: salesRes, returns: returnsRes, costMap: costMap).map((p) => p.toMap()).toList()
    ..sort((a, b) => (b['profit'] as double).compareTo(a['profit'] as double));
}

final monthTopProfitProvider = FutureProvider<List<Map<String, dynamic>>>((ref) => loadMonthTopProfit());

class _TopEarners extends ConsumerWidget {
  const _TopEarners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(monthTopProfitProvider);
    return _Card(
      color: const Color(0xFFFFF7E0),
      title: 'Top earners this month',
      action: 'View all',
      onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllProfitableProductsScreen())),
      children: [
        top.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const Text('Could not load', style: TextStyle(color: _C.muted)),
          data: (list) {
            if (list.isEmpty) return const Text('No sales this month yet', style: TextStyle(color: _C.muted));
            return Column(
              children: [
                for (var i = 0; i < list.length && i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: i == 0 ? const Color(0xFFFFD66B) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: _C.navy),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                list[i]['name'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.navy),
                              ),
                              Text(
                                '${formatQty(list[i]['qtySold'] as num)} sold · '
                                '${(list[i]['margin'] as double).toStringAsFixed(0)}% margin',
                                style: const TextStyle(fontSize: 12, color: _C.muted),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '+${_inr(list[i]['profit'] as double)}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _C.green),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ── running out ────────────────────────────────────────────────────────
class _RunningOut extends ConsumerWidget {
  const _RunningOut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // below zero is "purchase pending" (a job above), not running out
    final list = (ref.watch(lowStockListProvider).value ?? const <Product>[]).where((p) => p.stock > -0.0005).toList();
    return _Card(
      color: const Color(0xFFF1EEFB),
      title: 'Running out',
      action: list.isEmpty ? null : 'All ${list.length}',
      onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllLowStockScreen())),
      children: [
        if (list.isEmpty)
          const Text('Nothing is running low', style: TextStyle(color: _C.muted))
        else
          for (final p in list.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _C.navy),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.stock <= 0 ? const Color(0xFFFDE8E6) : const Color(0xFFFFF4DE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${formatQty(p.stockOnHand)} ${p.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.stock <= 0 ? const Color(0xFF8F1D14) : const Color(0xFF6B3A00),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// A coloured card with a title and an optional link on the right.
class _Card extends StatelessWidget {
  const _Card({required this.color, required this.title, required this.children, this.action, this.onAction});
  final Color color;
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.navy),
                ),
              ),
              if (action != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(foregroundColor: _C.ocean, minimumSize: const Size(48, 44)),
                  child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w700)),
                )
              else
                const SizedBox(height: 44),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}
