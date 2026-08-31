import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../models/purchase_order.dart';
import '../../models/supplier.dart';
import '../../config/providers.dart';
import '../../services/purchase_order_service.dart';

class PurchaseOrderScreen extends ConsumerStatefulWidget {
  const PurchaseOrderScreen({super.key});

  @override
  ConsumerState<PurchaseOrderScreen> createState() =>
      _PurchaseOrderScreenState();
}

class _PurchaseOrderScreenState extends ConsumerState<PurchaseOrderScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PurchaseOrder> _pendingOrders = [];
  List<PurchaseOrder> _orderedOrders = [];
  List<PurchaseOrder> _receivedOrders = [];
  List<PurchaseOrder> _cancelledOrders = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    try {
      final service = PurchaseOrderService();
      final pending = await service.getPurchaseOrders(status: 'pending');
      final ordered = await service.getPurchaseOrders(status: 'ordered');
      final received = await service.getPurchaseOrders(status: 'received');
      final cancelled = await service.getPurchaseOrders(status: 'cancelled');
      if (mounted) {
        setState(() {
          _pendingOrders = pending;
          _orderedOrders = ordered;
          _receivedOrders = received;
          _cancelledOrders = cancelled;
        });
      }
    } catch (e) {
      // handled silently
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Orders'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Pending (${_pendingOrders.length})'),
            Tab(text: 'Ordered (${_orderedOrders.length})'),
            Tab(text: 'Received (${_receivedOrders.length})'),
            Tab(text: 'Cancelled (${_cancelledOrders.length})'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadOrders),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: TabBarView(
          controller: _tabController,
          children: [
            _OrderList(
              orders: _pendingOrders,
              onLoad: _loadOrders,
              showActions: true,
              onEdit: _showEditPO,
            ),
            _OrderList(
              orders: _orderedOrders,
              onLoad: _loadOrders,
              showActions: true,
            ),
            _OrderList(orders: _receivedOrders, onLoad: _loadOrders),
            _OrderList(orders: _cancelledOrders, onLoad: _loadOrders),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showCreatePO(context),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New PO', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  void _showCreatePO(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreatePOSheet(
        onCreated: () {
          _loadOrders();
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showEditPO(BuildContext context, PurchaseOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreatePOSheet(
        existingOrder: order,
        onCreated: () {
          _loadOrders();
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<PurchaseOrder> orders;
  final VoidCallback onLoad;
  final bool showActions;
  final Function(BuildContext, PurchaseOrder)? onEdit;

  const _OrderList({
    required this.orders,
    required this.onLoad,
    this.showActions = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No orders', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _OrderCard(
          order: order,
          onLoad: onLoad,
          showActions: showActions,
          onEdit: onEdit,
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final PurchaseOrder order;
  final VoidCallback onLoad;
  final bool showActions;
  final Function(BuildContext, PurchaseOrder)? onEdit;

  const _OrderCard({
    required this.order,
    required this.onLoad,
    this.showActions = false,
    this.onEdit,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'ordered':
        return Colors.blue;
      case 'received':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _statusColor(order.status).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.shopping_bag, color: _statusColor(order.status)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Rs${order.totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _statusColor(order.status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                order.status.toUpperCase(),
                style: TextStyle(
                  color: _statusColor(order.status),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${order.supplierName ?? "No supplier"} | ${order.items.length} items',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            Text(
              DateFormat('dd MMM yyyy, hh:mm a').format(order.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                ...order.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (item.received)
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 16,
                                ),
                              const SizedBox(width: 4),
                              Expanded(child: Text(item.name)),
                            ],
                          ),
                        ),
                        Text(
                          'x${item.qty} @ Rs${item.price.toStringAsFixed(0)}',
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Rs${item.total.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                if (order.notes != null && order.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Notes: ${order.notes}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                if (showActions) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (order.status == 'pending') ...[
                        TextButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Order?'),
                                content: const Text(
                                  'This will permanently delete this purchase order.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await PurchaseOrderService().deletePurchaseOrder(
                                order.id,
                              );
                              onLoad();
                            }
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Cancel Order?'),
                                content: const Text(
                                  'This will mark the order as cancelled.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('No'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      'Cancel Order',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await PurchaseOrderService().cancelOrder(
                                order.id,
                              );
                              onLoad();
                            }
                          },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (onEdit != null) onEdit!(context, order);
                          },
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await PurchaseOrderService().updateStatus(
                              order.id,
                              'ordered',
                            );
                            onLoad();
                          },
                          child: const Text('Mark Ordered'),
                        ),
                      ],
                      if (order.status == 'ordered') ...[
                        TextButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Order?'),
                                content: const Text(
                                  'This will permanently delete this purchase order.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await PurchaseOrderService().deletePurchaseOrder(
                                order.id,
                              );
                              onLoad();
                            }
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Cancel Order?'),
                                content: const Text(
                                  'This will mark the order as cancelled.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('No'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      'Cancel Order',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await PurchaseOrderService().cancelOrder(
                                order.id,
                              );
                              onLoad();
                            }
                          },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Receive Order?'),
                                content: const Text(
                                  'This will add all items to inventory stock.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Receive'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await PurchaseOrderService().receiveOrder(
                                order.id,
                              );
                              onLoad();
                            }
                          },
                          child: const Text('Receive Order'),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatePOSheet extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  final PurchaseOrder? existingOrder;

  const _CreatePOSheet({required this.onCreated, this.existingOrder});

  @override
  ConsumerState<_CreatePOSheet> createState() => _CreatePOSheetState();
}

class _CreatePOSheetState extends ConsumerState<_CreatePOSheet> {
  List<Supplier> _suppliers = [];
  Supplier? _selectedSupplier;
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  final List<PurchaseOrderItem> _items = [];
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();
  bool _loading = false;
  String _stockFilter = 'all'; // all, low, critical, out

  bool get _isEditing => widget.existingOrder != null;

  double get _total => _items.fold(0.0, (sum, item) => sum + item.total);

  @override
  void initState() {
    super.initState();
    _loadData();
    // Pre-fill from existing order if editing
    if (_isEditing) {
      final order = widget.existingOrder!;
      _notesController.text = order.notes ?? '';
    }
  }

  Future<void> _loadData() async {
    final suppliers = await ref.read(supplierServiceProvider).getSuppliers();
    final products = await ref.read(productServiceProvider).getAllProducts();
    if (mounted) {
      setState(() {
        _suppliers = suppliers;
        _allProducts = products;
        _filteredProducts = products;

        // Pre-fill items from existing order
        if (_isEditing) {
          final order = widget.existingOrder!;
          _items.addAll(order.items);
          if (order.supplierId != null) {
            _selectedSupplier = suppliers
                .where((s) => s.id == order.supplierId)
                .firstOrNull;
          }
        }
      });
    }
  }

  void _addItem(Product product) {
    setState(() {
      final existing = _items.indexWhere((i) => i.productId == product.id);
      if (existing >= 0) {
        final item = _items[existing];
        _items[existing] = PurchaseOrderItem(
          productId: item.productId,
          name: item.name,
          qty: item.qty + 1,
          price: item.price,
        );
      } else {
        _items.add(
          PurchaseOrderItem(
            productId: product.id,
            name: product.name,
            qty: 1,
            price: product.purchasePrice,
          ),
        );
      }
    });
  }

  void _updateItemQty(int index, int delta) {
    setState(() {
      final item = _items[index];
      final newQty = item.qty + delta;
      if (newQty <= 0) {
        _items.removeAt(index);
      } else {
        _items[index] = PurchaseOrderItem(
          productId: item.productId,
          name: item.name,
          qty: newQty,
          price: item.price,
        );
      }
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _editItemPrice(int index) {
    final item = _items[index];
    final priceController = TextEditingController(
      text: item.price.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Price - ${item.name}'),
        content: TextField(
          controller: priceController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Price',
            border: OutlineInputBorder(),
            prefixText: 'Rs ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final price = double.tryParse(priceController.text);
              if (price != null && price > 0) {
                setState(() {
                  _items[index] = PurchaseOrderItem(
                    productId: item.productId,
                    name: item.name,
                    qty: item.qty,
                    price: price,
                  );
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showProductPicker() {
    setState(() {
      _filteredProducts = _allProducts;
      _stockFilter = 'all';
    });
    _filterProducts();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Add Products',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Search
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search product...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (v) => setSheetState(() => _filterProducts()),
                    ),
                    const SizedBox(height: 8),
                    // Stock filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            setSheetState,
                            'all',
                            'All (${_allProducts.length})',
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            setSheetState,
                            'out',
                            'Out of Stock',
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            setSheetState,
                            'critical',
                            'Critical',
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(setSheetState, 'low', 'Low Stock'),
                          const SizedBox(width: 6),
                          _buildFilterChip(setSheetState, 'ok', 'In Stock'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Product list
              Expanded(
                child: _filteredProducts.isEmpty
                    ? const Center(
                        child: Text(
                          'No products found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return _buildProductTile(product);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    StateSetter setSheetState,
    String value,
    String label,
  ) {
    final isSelected = _stockFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isSelected ? Colors.white : Colors.grey.shade700,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF667eea),
      backgroundColor: Colors.grey.shade100,
      onSelected: (_) {
        setSheetState(() {
          _stockFilter = value;
          _filterProducts();
        });
      },
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    var filtered = _allProducts
        .where((p) => p.name.toLowerCase().contains(query))
        .toList();

    switch (_stockFilter) {
      case 'out':
        filtered = filtered.where((p) => p.stock == 0).toList();
        break;
      case 'critical':
        filtered = filtered.where((p) => p.stock > 0 && p.stock < 5).toList();
        break;
      case 'low':
        filtered = filtered.where((p) => p.stock >= 5 && p.isLowStock).toList();
        break;
      case 'ok':
        filtered = filtered.where((p) => !p.isLowStock).toList();
        break;
    }

    // Sort: out of stock first, then critical, then low
    filtered.sort((a, b) {
      if (a.stock == 0 && b.stock != 0) return -1;
      if (a.stock != 0 && b.stock == 0) return 1;
      return a.stock.compareTo(b.stock);
    });

    _filteredProducts = filtered;
  }

  Widget _buildProductTile(Product product) {
    final stock = product.stock;
    Color stockColor;
    String stockLabel;
    IconData stockIcon;

    if (stock == 0) {
      stockColor = Colors.red;
      stockLabel = 'OUT';
      stockIcon = Icons.error_outline;
    } else if (stock < 5) {
      stockColor = Colors.orange;
      stockLabel = 'CRIT';
      stockIcon = Icons.warning_amber;
    } else if (product.isLowStock) {
      stockColor = Colors.amber.shade700;
      stockLabel = 'LOW';
      stockIcon = Icons.trending_down;
    } else {
      stockColor = Colors.green;
      stockLabel = '$stock';
      stockIcon = Icons.check_circle_outline;
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: stockColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(stockIcon, color: stockColor, size: 20),
      ),
      title: Text(product.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        'Rs${product.purchasePrice.toStringAsFixed(0)} | Stock: $stock ${product.unit}',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: stockColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          stockLabel,
          style: TextStyle(
            color: stockColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      onTap: () {
        _addItem(product);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isEditing ? 'Edit Purchase Order' : 'Create Purchase Order',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Supplier selection
            DropdownButtonFormField<String>(
              value: _selectedSupplier?.id,
              decoration: const InputDecoration(
                labelText: 'Supplier',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('None', style: TextStyle(color: Colors.grey)),
                ),
                ..._suppliers.map(
                  (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                ),
              ],
              onChanged: (id) {
                if (id == null || id.isEmpty) {
                  setState(() => _selectedSupplier = null);
                } else {
                  final supplier = _suppliers.firstWhere((s) => s.id == id);
                  setState(() => _selectedSupplier = supplier);
                }
              },
            ),
            const SizedBox(height: 12),

            // Add products button
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _showProductPicker,
                icon: const Icon(Icons.add),
                label: const Text('Add Products'),
              ),
            ),
            const SizedBox(height: 12),

            // Items list
            if (_items.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: GestureDetector(
                          onTap: () => _editItemPrice(index),
                          child: Text(
                            'Rs${item.price.toStringAsFixed(0)} x ${item.qty} = Rs${item.total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 20,
                              ),
                              onPressed: () => _updateItemQty(index, -1),
                            ),
                            Text(
                              '${item.qty}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 20,
                              ),
                              onPressed: () => _updateItemQty(index, 1),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () => _removeItem(index),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Rs${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // Notes
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Submit
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading || _items.isEmpty ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF11998e),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _isEditing
                            ? 'Update Purchase Order'
                            : 'Create Purchase Order',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _loading = true);

    try {
      final po = PurchaseOrder(
        id: _isEditing ? widget.existingOrder!.id : '',
        supplierId: _selectedSupplier?.id,
        supplierName: _selectedSupplier?.name,
        items: _items,
        totalAmount: _total,
        status: _isEditing ? widget.existingOrder!.status : 'pending',
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        createdAt: _isEditing
            ? widget.existingOrder!.createdAt
            : DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (_isEditing) {
        await PurchaseOrderService().updatePurchaseOrder(po);
      } else {
        await PurchaseOrderService().createPurchaseOrder(po);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Purchase order updated' : 'Purchase order created',
            ),
            backgroundColor: Colors.green,
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
