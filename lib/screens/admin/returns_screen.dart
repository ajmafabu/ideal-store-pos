import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../models/sale.dart';
import '../../models/product_return.dart';
import '../../utils/app_timezone.dart';

class ReturnsScreen extends ConsumerStatefulWidget {
  const ReturnsScreen({super.key});

  @override
  ConsumerState<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends ConsumerState<ReturnsScreen> {
  List<Map<String, dynamic>> _weekBills = [];
  bool _loadingWeekBills = true;
  String _billSearch = '';
  Map<String, dynamic>? _selectedBill;
  List<CartItem> _billItems = [];
  final Map<String, int> _returnQty = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadWeekBills();
  }

  Future<void> _loadWeekBills() async {
    setState(() => _loadingWeekBills = true);
    try {
      final bills = await ref.read(returnServiceProvider).getRecentWeekSales();
      if (mounted) {
        setState(() {
          _weekBills = bills;
          _loadingWeekBills = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingWeekBills = false);
    }
  }

  void _selectBill(Map<String, dynamic>? bill) {
    setState(() {
      _selectedBill = bill;
      _returnQty.clear();
      if (bill != null) {
        final itemsRaw = bill['items'] as List<dynamic>?;
        _billItems = itemsRaw
                ?.map((e) => CartItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
      } else {
        _billItems = [];
      }
    });
  }

  List<Map<String, dynamic>> get _filteredBills {
    if (_billSearch.isEmpty) return _weekBills;
    final q = _billSearch.toLowerCase();
    return _weekBills.where((b) {
      final id = (b['id'] as String? ?? '').toLowerCase();
      final customer =
          (b['customers'] as Map<String, dynamic>?)?['name']?.toString().toLowerCase() ?? '';
      return id.contains(q) || customer.contains(q);
    }).toList();
  }

  List<CartItem> get _selectedItems =>
      _billItems.where((item) => (_returnQty[item.productId] ?? 0) > 0).toList();

  double get _totalRefund => _selectedItems.fold(
      0.0, (sum, item) => sum + item.price * (_returnQty[item.productId] ?? 0));

  int get _totalReturnQty =>
      _returnQty.values.fold(0, (sum, q) => sum + q);

  @override
  Widget build(BuildContext context) {
    final returnsAsync = ref.watch(returnsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Returns'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(returnsProvider);
              _loadWeekBills();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Bills Section ──
                SliverToBoxAdapter(
                  child: _buildBillsSection(),
                ),

                // ── Bill Items Section ──
                if (_selectedBill != null)
                  SliverToBoxAdapter(
                    child: _buildBillItemsSection(),
                  ),

                // ── History Header ──
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Return History',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.grey),
                    ),
                  ),
                ),

                // ── Returns List ──
                returnsAsync.when(
                  loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => SliverFillRemaining(
                    child: Center(child: Text('Error: $e')),
                  ),
                  data: (returns) {
                    if (returns.isEmpty) {
                      return const SliverFillRemaining(
                        child: Center(child: Text('No returns recorded')),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final r = returns[index] as ProductReturn;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.replay,
                                    color: Colors.orange, size: 20),
                              ),
                              title: Text(r.productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Qty: ${r.quantity} | Rs${r.refundAmount.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (r.originalSaleId != null)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Sale: #${r.originalSaleId!.substring(0, r.originalSaleId!.length > 8 ? 8 : r.originalSaleId!.length)}',
                                        style: const TextStyle(
                                            fontSize: 10, color: Colors.blue),
                                      ),
                                    ),
                                  if (r.reason != null && r.reason!.isNotEmpty)
                                    Text(r.reason!,
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                              trailing: Text(
                                DateFormat('dd MMM\nhh:mm a').format(r.createdAt),
                                style: const TextStyle(fontSize: 11),
                                textAlign: TextAlign.end,
                              ),
                            ),
                          );
                        },
                        childCount: returns.length,
                      ),
                    );
                  },
                ),

                // Bottom padding for cart bar
                SliverToBoxAdapter(
                    child: SizedBox(height: _selectedItems.isNotEmpty ? 100 : 30)),
              ],
            ),
          ),

          // ── Return Cart Bar ──
          if (_selectedItems.isNotEmpty) _buildCartBar(),
        ],
      ),
    );
  }

  Widget _buildBillsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Select Bill to Return From',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue.shade700),
              ),
              const Spacer(),
              if (_selectedBill != null)
                TextButton.icon(
                  onPressed: () => _selectBill(null),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search bill ID or customer...',
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.blue.shade300)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
              fillColor: Colors.white,
              filled: true,
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => setState(() => _billSearch = v),
          ),
          const SizedBox(height: 8),
          if (_loadingWeekBills)
            const SizedBox(
              height: 60,
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_filteredBills.isEmpty)
            SizedBox(
              height: 60,
              child: Center(
                child: Text(
                  _weekBills.isEmpty
                      ? 'No bills in last 7 days'
                      : 'No matching bills',
                  style:
                      TextStyle(color: Colors.blue.shade400, fontSize: 13),
                ),
              ),
            )
          else
            SizedBox(
              height: _selectedBill != null ? 120 : 200,
              child: ListView.builder(
                itemCount: _filteredBills.length,
                itemBuilder: (context, index) {
                  final bill = _filteredBills[index];
                  final id = bill['id'] as String? ?? '';
                  final shortId = id.length > 8 ? id.substring(0, 8) : id;
                  final amount =
                      (bill['final_amount'] as num?)?.toDouble() ?? 0;
                  final date = DateTime.tryParse(
                      bill['created_at'] as String? ?? '');
                  final isCredit = bill['is_credit'] == true;
                  final customerName =
                      (bill['customers'] as Map<String, dynamic>?)?['name']
                              as String? ??
                          'Walk-in';
                  final items = bill['items'] as List<dynamic>?;
                  final itemCount = items?.length ?? 0;
                  final isSelected = _selectedBill?['id'] == id;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    color: isSelected ? Colors.blue.shade100 : null,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: isSelected ? Colors.blue : Colors.grey,
                      ),
                      title: Row(
                        children: [
                          Text('#$shortId',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(width: 6),
                          Text(customerName,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          if (date != null)
                            Text(DateFormat('dd MMM, hh:mm a').format(date),
                                style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 8),
                          Text('$itemCount items',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500)),
                          if (isCredit) ...[
                            const SizedBox(width: 8),
                            const Text('Credit',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.orange)),
                          ],
                        ],
                      ),
                      trailing: Text('Rs ${amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      onTap: () => _selectBill(bill),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBillItemsSection() {
    final billId = (_selectedBill!['id'] as String);
    final shortId = billId.length > 8 ? billId.substring(0, 8) : billId;
    final customerName =
        (_selectedBill!['customers'] as Map<String, dynamic>?)?['name']
                as String? ??
            'Walk-in';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_cart, color: Colors.green.shade700, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bill #$shortId — $customerName',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.green.shade800),
                    ),
                    Text(
                      'Select items to return',
                      style: TextStyle(
                          fontSize: 11, color: Colors.green.shade600),
                    ),
                  ],
                ),
              ),
              if (_selectedItems.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_selectedItems.length} items | Rs ${_totalRefund.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Items list
          ...List.generate(_billItems.length, (index) {
            final item = _billItems[index];
            final returnQty = _returnQty[item.productId] ?? 0;
            final isSelected = returnQty > 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: isSelected ? Colors.orange.shade50 : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    // Selection indicator
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _returnQty.remove(item.productId);
                          } else {
                            _returnQty[item.productId] = 1;
                          }
                        });
                      },
                      child: Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 22,
                        color: isSelected ? Colors.orange : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Product info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text('Rs ${item.price.toStringAsFixed(0)} × ',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600)),
                              Text('Qty: ${item.qty}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600)),
                              if (item.tier != 'normal') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: item.tier == 'wholesale'
                                        ? Colors.blue.withValues(alpha: 0.1)
                                        : Colors.purple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.tier.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: item.tier == 'wholesale'
                                            ? Colors.blue
                                            : Colors.purple,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Qty controls
                    if (isSelected)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _qtyButton(
                              icon: Icons.remove,
                              onTap: () {
                                setState(() {
                                  final current =
                                      _returnQty[item.productId] ?? 1;
                                  if (current <= 1) {
                                    _returnQty.remove(item.productId);
                                  } else {
                                    _returnQty[item.productId] = current - 1;
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 36,
                              alignment: Alignment.center,
                              child: Text(
                                '$returnQty',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            _qtyButton(
                              icon: Icons.add,
                              onTap: () {
                                setState(() {
                                  final current =
                                      _returnQty[item.productId] ?? 0;
                                  if (current < item.qty) {
                                    _returnQty[item.productId] = current + 1;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        'Max: ${item.qty}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _qtyButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: Colors.orange.shade800),
      ),
    );
  }

  Widget _buildCartBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Return items summary
            SizedBox(
              height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _selectedItems.map<Widget>((item) {
                  final qty = _returnQty[item.productId] ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${item.name} x$qty',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            setState(() => _returnQty.remove(item.productId));
                          },
                          child: Icon(Icons.close,
                              size: 14, color: Colors.orange.shade800),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            // Total + Submit
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Refund',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    Text(
                      'Rs ${_totalRefund.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.orange),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '$_totalReturnQty items',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _submitting ? null : _submitReturns,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, color: Colors.white, size: 18),
                  label: const Text('Finish Return',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReturns() async {
    if (_selectedItems.isEmpty || _selectedBill == null) return;

    // Show reason dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _ReasonDialog(),
    );
    if (reason == null) return; // cancelled

    setState(() => _submitting = true);

    try {
      final saleId = _selectedBill!['id'] as String;
      final returns = <ProductReturn>[];

      for (final item in _selectedItems) {
        final qty = _returnQty[item.productId] ?? 0;
        if (qty <= 0) continue;

        returns.add(ProductReturn(
          id: '',
          productId: item.productId,
          productName: item.name,
          quantity: qty,
          unitPrice: item.price,
          refundAmount: item.price * qty,
          reason: reason,
          createdAt: AppTimezone.nowIst(),
          originalSaleId: saleId,
          returnAmount: item.price * qty,
        ));
      }

      await ref.read(returnServiceProvider).createBulkReturn(
            originalSaleId: saleId,
            returns: returns,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${returns.length} return(s) recorded'),
            backgroundColor: Colors.green,
          ),
        );
        _selectBill(null);
        ref.invalidate(returnsProvider);
        _loadWeekBills();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _ReasonDialog extends StatefulWidget {
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  String _reason = 'customer_changed_mind';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Return Reason'),
      content: DropdownButtonFormField<String>(
        value: _reason,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'expired', child: Text('Expired')),
          DropdownMenuItem(value: 'wrong_item', child: Text('Wrong Item')),
          DropdownMenuItem(
              value: 'customer_changed_mind',
              child: Text('Customer Changed Mind')),
          DropdownMenuItem(value: 'damaged', child: Text('Damaged')),
          DropdownMenuItem(value: 'other', child: Text('Other')),
        ],
        onChanged: (v) => setState(() => _reason = v ?? _reason),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _reason),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
