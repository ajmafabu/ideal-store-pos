import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/product.dart';
import '../../services/stock_check_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/product_search.dart';
import '../../utils/qty_format.dart';
import '../../utils/stock_health.dart';
import '../../widgets/barcode_scanner.dart';
import 'stock_health_screen.dart';

/// Count the shelf (18 Oct 2026). "Today" is a short list made from the
/// products' importance (A weekly, B monthly, C every 3 months); "All" counts
/// any product by name, Tamil name or barcode. Each count sets the stock to
/// what is on the shelf and keeps the difference with a reason.
class StockCheckScreen extends ConsumerStatefulWidget {
  const StockCheckScreen({super.key});

  @override
  ConsumerState<StockCheckScreen> createState() => _StockCheckScreenState();
}

class _StockCheckScreenState extends ConsumerState<StockCheckScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _service = StockCheckService();

  /// Counted in this session: product id → difference found.
  final Map<String, double> _done = {};
  String _query = '';

  /// "By category": the category being walked (null = the list of them).
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stockHealthProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Count Stock'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Today\'s list'), Tab(text: 'By category'), Tab(text: 'Any product')],
          ),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(ErrorMessages.parse(e))),
          data: (d) => TabBarView(
            children: [
              _todayTab(d),
              _categoryTab(d),
              _anyTab(d),
            ],
          ),
        ),
      ),
    );
  }

  Widget _todayTab(StockHealthData d) {
    final due = d.health.dueToday;
    final scheme = Theme.of(context).colorScheme;
    if (due.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nothing due today. Every product has been counted on time.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final left = due.where((c) => !_done.containsKey(c.product.id)).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  left == 0 ? 'Today\'s list is done.' : '$left of ${due.length} left · about ${(left * 0.5).ceil()} min',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Text('A weekly · B monthly · C 3 months', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: due.length,
            itemBuilder: (_, i) {
              final c = due[i];
              return _productTile(
                c.product,
                cls: c.cls,
                detail: c.lastCounted == null
                    ? 'never counted'
                    : 'last counted ${DateFormat('d MMM').format(c.lastCounted!)}',
              );
            },
          ),
        ),
      ],
    );
  }

  /// When each product was last really counted (shelf counts only).
  Map<String, DateTime> _lastCounted(StockHealthData d) {
    final last = <String, DateTime>{};
    for (final c in d.counts.where((c) => c.isShelfCount)) {
      final prev = last[c.productId];
      if (prev == null || c.at.isAfter(prev)) last[c.productId] = c.at;
    }
    return last;
  }

  /// Walk one shelf or category at a time: the full count (23 Oct 2026).
  /// "Counted" = counted in the last 30 days or in this session.
  Widget _categoryTab(StockHealthData d) {
    final scheme = Theme.of(context).colorScheme;
    final last = _lastCounted(d);
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    bool counted(Product p) => _done.containsKey(p.id) || (last[p.id]?.isAfter(monthAgo) ?? false);
    final products = d.products.where((p) => !p.hasVariants && !p.isHidden).toList();
    final byCat = <String, List<Product>>{};
    for (final p in products) {
      byCat.putIfAbsent((p.category ?? '').trim().isEmpty ? 'No category' : p.category!.trim(), () => []).add(p);
    }
    final allDone = products.where(counted).length;

    if (_category == null || !byCat.containsKey(_category)) {
      final cats = byCat.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text('Whole shop: $allDone of ${products.length} counted in the last 30 days',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(
              value: products.isEmpty ? 0 : allDone / products.length,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          for (final c in cats)
            Builder(builder: (_) {
              final list = byCat[c]!;
              final done = list.where(counted).length;
              return ListTile(
                title: Text(c, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('$done of ${list.length} counted'),
                leading: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: list.isEmpty ? 0 : done / list.length,
                    strokeWidth: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: done == list.length ? Colors.green.shade600 : scheme.primary,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _category = c),
              );
            }),
        ],
      );
    }

    final list = byCat[_category]!..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final done = list.where(counted).length;
    return Column(
      children: [
        Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: ListTile(
            leading: IconButton(
              tooltip: 'All categories',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _category = null),
            ),
            title: Text(_category!, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(done == list.length
                ? 'All ${list.length} counted'
                : '$done of ${list.length} counted · ${list.length - done} left'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              final when = last[p.id];
              return _productTile(
                p,
                cls: d.health.classes[p.id],
                detail: _done.containsKey(p.id)
                    ? null
                    : (when != null && when.isAfter(monthAgo) ? 'counted ${DateFormat('d MMM').format(when)}' : null),
                countedBefore: counted(p),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _anyTab(StockHealthData d) {
    final found = _query.trim().isEmpty ? const <Product>[] : searchProducts(d.products, _query).take(60).toList();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            autofocus: Platform.isWindows,
            decoration: InputDecoration(
              hintText: 'Name, Tamil name or barcode',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Platform.isAndroid || Platform.isIOS
                  ? IconButton(tooltip: 'Scan barcode', icon: const Icon(Icons.qr_code_scanner), onPressed: () => _scan(d))
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
            // a barcode gun types the code and Enter: open that product
            onSubmitted: (v) {
              final exact = d.products.where((p) => (p.barcode ?? '') == v.trim()).toList();
              if (exact.length == 1) {
                _count(exact.first);
              } else if (found.isNotEmpty) {
                _count(found.first);
              }
            },
          ),
        ),
        Expanded(
          child: found.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty ? 'Type or scan to find a product' : 'No product "${_query.trim()}"',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: found.length,
                  itemBuilder: (_, i) => _productTile(found[i], cls: d.health.classes[found[i].id]),
                ),
        ),
      ],
    );
  }

  Widget _productTile(Product p, {CountClass? cls, String? detail, bool countedBefore = false}) {
    final scheme = Theme.of(context).colorScheme;
    final diff = _done[p.id];
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: diff == null
            ? (countedBefore ? Colors.green.shade50 : scheme.surfaceContainerHighest)
            : (diff.abs() < 0.001 ? Colors.green.shade100 : Colors.orange.shade100),
        child: diff == null
            ? (countedBefore
                ? Icon(Icons.check, color: Colors.green.shade700, size: 18)
                : Text(cls?.label ?? '', style: const TextStyle(fontWeight: FontWeight.bold)))
            : Icon(diff.abs() < 0.001 ? Icons.check : Icons.edit_note,
                color: diff.abs() < 0.001 ? Colors.green.shade800 : Colors.orange.shade900, size: 20),
      ),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          if ((p.tamilName ?? '').isNotEmpty) p.tamilName!,
          if (diff != null) diff.abs() < 0.001 ? 'matched' : 'difference ${diff > 0 ? '+' : ''}${formatQty(diff)}',
          if (detail != null) detail,
        ].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        'app ${formatQty(p.stock)}',
        style: TextStyle(fontWeight: FontWeight.bold, color: p.stock < 0 ? scheme.error : null),
      ),
      onTap: () => _count(p),
    );
  }

  Future<void> _scan(StockHealthData d) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || !mounted) return;
    final p = d.products.where((x) => (x.barcode ?? '') == code.trim()).firstOrNull;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No product with barcode $code')));
      return;
    }
    await _count(p);
  }

  Future<void> _count(Product p) async {
    final result = await showCountSheet(context, p, service: _service);
    if (result == null || !mounted) return;
    final diff = (result['difference'] as num?)?.toDouble() ?? 0;
    final moved = (result['moved'] as num?)?.toDouble() ?? 0;
    final stock = (result['stock'] as num?)?.toDouble() ?? 0;
    setState(() => _done[p.id] = diff);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text([
          diff.abs() < 0.001 ? '${p.name}: matched' : '${p.name}: ${diff > 0 ? '+' : ''}${formatQty(diff)} corrected',
          // the till kept selling while the shelf was counted
          if (moved.abs() >= 0.001)
            '${formatQty(moved.abs())} ${moved < 0 ? 'sold' : 'added'} while counting · now ${formatQty(stock)}',
        ].join(' · ')),
        duration: const Duration(seconds: 3),
      ),
    );
    _search.clear();
    setState(() => _query = '');
    if (Platform.isWindows) _searchFocus.requestFocus();
  }
}

/// Count one product's shelf (also opened from the product page).
/// Returns {stock, moved, difference}, or null when closed without saving.
Future<Map<String, dynamic>?> showCountSheet(BuildContext context, Product p, {StockCheckService? service}) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CountSheet(product: p, service: service ?? StockCheckService()),
    );

/// Type what is on the shelf; the difference and a reason are saved.
class _CountSheet extends StatefulWidget {
  const _CountSheet({required this.product, required this.service});
  final Product product;
  final StockCheckService service;

  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  final _qty = TextEditingController();
  String _reason = countReasons.first;
  bool _saving = false;
  String? _error;

  /// What the app says as counting begins, fresh from the database (the
  /// list may be minutes old). Sales after this are kept when saving.
  double? _appQty;

  @override
  void initState() {
    super.initState();
    widget.service.currentStock(widget.product.id).then((v) {
      if (mounted) setState(() => _appQty = v);
    }).catchError((_) {});
  }

  double get _app => _appQty ?? widget.product.stock;

  bool get _loose => const {'kg', 'g', 'gm', 'gram', 'ltr', 'litre', 'l', 'ml'}
      .contains(widget.product.unit.toLowerCase().trim());

  double? get _counted => double.tryParse(_qty.text.trim());

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final counted = _counted;
    if (counted == null || counted < 0) {
      setState(() => _error = 'Enter what is on the shelf (0 or more)');
      return;
    }
    if (!_loose && counted != counted.roundToDouble()) {
      setState(() => _error = 'Whole ${widget.product.unit} only');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final reason = (counted - _app).abs() < 0.001 ? 'Matched' : _reason;
      final result = await widget.service.saveCount(widget.product, counted, reason, appQty: _app);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ErrorMessages.parse(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = widget.product;
    final counted = _counted;
    final diff = counted == null ? null : counted - _app;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if ((p.tamilName ?? '').isNotEmpty) Text(p.tamilName!, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              'The app says ${formatQty(_app)} ${p.unit}${_appQty == null ? ' …' : ''}',
              style: TextStyle(fontSize: 15, color: _app < 0 ? scheme.error : scheme.onSurfaceVariant),
            ),
            if (_app < -0.0005) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Purchase pending: ${formatQty(-_app)} ${p.unit} were sold before the purchase bill was '
                  'entered. Enter that purchase first. If you count now and enter the purchase later, '
                  'those goods are counted twice.',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _qty,
              autofocus: true,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              keyboardType: TextInputType.numberWithOptions(decimal: _loose),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(_loose ? r'^\d*\.?\d{0,3}' : r'^\d*'))],
              decoration: InputDecoration(
                labelText: 'On the shelf (${p.unit})',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(),
            ),
            if (diff != null) ...[
              const SizedBox(height: 8),
              Text(
                diff.abs() < 0.001
                    ? 'Matches the app'
                    : 'Difference ${diff > 0 ? '+' : ''}${formatQty(diff)} ${p.unit}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: diff.abs() < 0.001 ? Colors.green.shade700 : Colors.orange.shade900,
                ),
              ),
            ],
            if (diff != null && diff.abs() >= 0.001) ...[
              const SizedBox(height: 10),
              const Text('Why?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in countReasons)
                    ChoiceChip(label: Text(r), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
                ],
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Text('Save count', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
