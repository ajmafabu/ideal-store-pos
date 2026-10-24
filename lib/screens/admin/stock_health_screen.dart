import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/providers.dart';
import '../../models/product.dart';
import '../../services/stock_check_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/qty_format.dart';
import '../../utils/stock_health.dart';
import 'hidden_products_screen.dart';
import 'stock_check_screen.dart';

/// Everything the stock check needs, loaded together.
class StockHealthData {
  StockHealthData(this.health, this.products, this.counts);
  final StockHealth health;
  final List<Product> products;
  final List<StockCount> counts;
}

final stockHealthProvider = FutureProvider.autoDispose<StockHealthData>((ref) async {
  final products = await ref.read(productServiceProvider).getAllProducts();
  final service = StockCheckService();
  final results = await Future.wait([
    service.recentCounts(),
    service.batchTotals(),
    ref.read(saleServiceProvider).getProductSalesStats(),
  ]);
  final counts = results[0] as List<StockCount>;
  final batches = results[1] as Map<String, double>;
  final stats = results[2] as Map<String, Map<String, dynamic>>;
  final byId = {for (final p in products) p.id: p};
  final value30 = <String, double>{
    for (final e in stats.entries)
      e.key: ((e.value['qty30d'] as num?)?.toDouble() ?? 0) * (byId[e.key]?.sellingPrice ?? 0),
  };
  final health = StockHealth.compute(
    products: products,
    counts: counts,
    batchTotals: batches,
    salesValue30d: value30,
    now: DateTime.now(),
  );
  return StockHealthData(health, products, counts);
});

/// Stock health (18 Oct 2026): how true the stock figures are, and what to
/// fix. Accuracy from the counts of the last 30 days; products sold before
/// their purchase was entered; products with no cost price; products not
/// counted for a month; the biggest count differences; batches that do
/// not add up.
class StockHealthScreen extends ConsumerWidget {
  const StockHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stockHealthProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Health'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(stockHealthProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const StockCheckScreen()));
          ref.invalidate(stockHealthProvider);
        },
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Count stock'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(ErrorMessages.parse(e), textAlign: TextAlign.center),
          ),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(stockHealthProvider),
          child: _body(context, d),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, StockHealthData d) {
    final h = d.health;
    final scheme = Theme.of(context).colorScheme;
    final byId = {for (final p in d.products) p.id: p};
    final acc = h.accuracyPercent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // fill the 84 box (on its own the ring is only 36 wide)
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: (acc ?? 0) / 100,
                          strokeWidth: 8,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: acc == null
                              ? scheme.outline
                              : (acc >= 95 ? Colors.green.shade600 : (acc >= 80 ? Colors.orange.shade700 : scheme.error)),
                        ),
                      ),
                      // inside the ring, whatever the width of "100%"
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            acc == null ? '–' : '${acc.toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Stock accuracy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        h.countsLast30 == 0
                            ? 'No counts in the last 30 days yet. Tap Count stock to start.'
                            : '${h.matchedLast30} of ${h.countsLast30} counts in the last 30 days matched the shelf.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Today\'s counting list: ${h.dueToday.length} product${h.dueToday.length == 1 ? '' : 's'}',
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _section(
          context,
          icon: Icons.local_shipping_outlined,
          color: scheme.error,
          title: 'Purchase pending (below zero)',
          help: 'Sold before the purchase bill was entered. Enter the purchase; the stock then comes right.',
          rows: [
            for (final p in h.belowZero)
              _row(context, p.name, '${formatQty(p.stock)} ${p.unit}', '${formatQty(-p.stock)} sold ahead'),
          ],
        ),
        _section(
          context,
          icon: Icons.money_off_outlined,
          color: Colors.orange.shade800,
          title: 'No cost price',
          help: 'Sales of these count as almost 100% profit. Enter the purchase price on the product.',
          rows: [
            for (final p in h.noCost) _row(context, p.name, 'cost ₹0', 'sells ₹${p.sellingPrice.toStringAsFixed(2)}'),
          ],
        ),
        _section(
          context,
          icon: Icons.difference_outlined,
          color: Colors.deepPurple,
          title: 'Biggest count differences (30 days)',
          help: 'The shelf was not what the app said. The reason tells you why.',
          rows: [
            for (final c in h.bigDifferences)
              _row(
                context,
                byId[c.productId]?.name ?? 'Product removed',
                '${c.difference > 0 ? '+' : ''}${formatQty(c.difference)}',
                '${formatQty(c.systemQty)} → ${formatQty(c.countedQty)} · ${c.reason ?? ''} · ${DateFormat('d MMM').format(c.at)}',
              ),
          ],
        ),
        _section(
          context,
          icon: Icons.history_toggle_off,
          color: Colors.blueGrey,
          title: 'Not counted in 30 days',
          help: 'Best sellers first. The counting list takes these a few at a time.',
          rows: [
            for (final p in h.notCounted)
              _row(context, p.name, '${formatQty(p.stock)} ${p.unit}', 'class ${h.classes[p.id]?.label ?? 'C'}'),
          ],
        ),
        _section(
          context,
          icon: Icons.layers_outlined,
          color: Colors.teal,
          title: 'Batches do not add up',
          help: 'Old drift between the stock and the cost batches. Counting the product fixes it.',
          rows: [
            for (final m in h.batchMismatches)
              _row(
                context,
                m.product.name,
                'stock ${formatQty(m.product.stockOnHand)}',
                'batches ${formatQty(m.batchTotal)}',
              ),
          ],
        ),
        Card(
          margin: const EdgeInsets.only(top: 10),
          child: ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hidden products', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${d.products.where((p) => p.isHidden).length} empty for 30 days · tap to show one again',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HiddenProductsScreen())),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String name, String value, String detail) {
    return ListTile(
      dense: true,
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String help,
    required List<Widget> rows,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        leading: Icon(icon, color: rows.isEmpty ? Colors.green.shade600 : color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          rows.isEmpty ? 'All good' : '${rows.length} product${rows.length == 1 ? '' : 's'}',
          style: TextStyle(color: rows.isEmpty ? Colors.green.shade700 : color, fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(help, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
          // long lists: the first 100 (the rest after fixing these)
          ...rows.take(100),
          if (rows.length > 100)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('… and ${rows.length - 100} more', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}
