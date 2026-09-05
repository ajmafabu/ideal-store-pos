import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/providers.dart';
import '../../../config/desktop_billing_provider.dart';
import '../../../models/sale.dart';
import '../../../services/offline_service.dart';
import '../../../services/thermal_printer_service.dart';
import '../../../utils/app_timezone.dart';
import '../../../utils/logger.dart';
import '../../../utils/thermal_invoice.dart';

class DesktopSalesHistoryDialog extends ConsumerStatefulWidget {
  final Function(Sale)? onEditSale;
  const DesktopSalesHistoryDialog({super.key, this.onEditSale});

  @override
  ConsumerState<DesktopSalesHistoryDialog> createState() =>
      _DesktopSalesHistoryDialogState();
}

class _DesktopSalesHistoryDialogState
    extends ConsumerState<DesktopSalesHistoryDialog> {
  final _searchController = TextEditingController();
  String _query = '';
  List<Sale> _offlineSales = [];
  bool _loadedOffline = false;

  @override
  void initState() {
    super.initState();
    _loadOfflineSales();
  }

  Future<void> _loadOfflineSales() async {
    final offline = OfflineService();
    final cached = offline.getCachedSalesHistory();
    final pending = offline.getPendingSales();
    final all = <String, Map<String, dynamic>>{};
    for (final s in cached) {
      final id = s['id']?.toString() ?? '';
      if (id.isNotEmpty) all[id] = s;
    }
    for (final s in pending) {
      final id = s['id']?.toString() ?? '';
      if (id.isNotEmpty) all[id] = s;
    }
    final merged = all.values.toList()
      ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
    final sales = <Sale>[];
    for (final e in merged) {
      try {
        sales.add(Sale.fromJson(e));
      } catch (e) {
        Logger.warning('Failed to parse cached sale entry: $e');
      }
    }
    if (mounted) {
      setState(() {
        _offlineSales = sales;
        _loadedOffline = true;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Sale> _filter(List<Sale> sales) {
    if (_query.isEmpty) return sales;
    final q = _query.toLowerCase();
    return sales.where((s) {
      final amount = s.finalAmount.toStringAsFixed(0);
      final customer = (s.customerName ?? 'walk-in').toLowerCase();
      final payment = s.paymentMethod.toLowerCase();
      final id = s.id.toLowerCase();
      return amount.contains(q) ||
          customer.contains(q) ||
          payment.contains(q) ||
          id.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesHistoryProvider);

    // Merge: online provider data + offline Hive data (always fresh from Hive)
    final List<Sale> displaySales;
    final onlineSales = salesAsync.hasValue ? salesAsync.value : null;
    if (onlineSales != null && onlineSales.isNotEmpty) {
      // Online data available — merge with offline to include unsynced sales
      final all = <String, Sale>{};
      for (final s in onlineSales) {
        all[s.id] = s;
      }
      for (final s in _offlineSales) {
        if (!all.containsKey(s.id)) {
          all[s.id] = s;
        }
      }
      displaySales = all.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else {
      // Offline or loading — use Hive data directly (instant, no network wait)
      displaySales = _offlineSales;
    }

    return AlertDialog(
      title: Row(
        children: [
          const Text('Sales History'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () {
              ref.invalidate(salesHistoryProvider);
              ref.invalidate(productsProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sales history refreshed'),
                  backgroundColor: Color(0xFF059669),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          if (!_loadedOffline)
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (onlineSales == null && _loadedOffline)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('OFFLINE', style: TextStyle(fontSize: 10, color: Colors.orange)),
            ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by customer, amount, payment...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _query = '';
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: displaySales.isEmpty
                  ? Center(
                      child: Text(
                        salesAsync.isLoading ? 'Loading...' : 'No sales yet',
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final filtered = _filter(displaySales);
                        if (filtered.isEmpty) {
                          return const Center(child: Text('No results found'));
                        }
                        return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final sale = filtered[index];
                      final bool isPaid = !sale.isCredit || sale.dueAmount <= 0;
                      return ListTile(
                        dense: true,
                        title: Text(
                          'Rs${sale.finalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${sale.customerName ?? "Walk-in"} | ${sale.items.length} products | ${sale.paymentMethod.toUpperCase()} | ${AppTimezone.formatDateTime(sale.createdAt)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isPaid
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isPaid
                                      ? Colors.green.shade200
                                      : Colors.red.shade200,
                                ),
                              ),
                              child: Text(
                                isPaid
                                    ? 'PAID'
                                    : 'DUE: Rs${sale.dueAmount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isPaid
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'details',
                                  child: Text('View Details'),
                                ),
                                PopupMenuItem(
                                  value: 'print_usb',
                                  child: Text('Print (USB/Network)'),
                                ),
                                PopupMenuItem(
                                  value: 'print_bluetooth',
                                  child: Text('Print (Bluetooth)'),
                                ),
                                PopupMenuItem(
                                  value: 'share',
                                  child: Text('Share PDF'),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit Sale'),
                                ),
                                PopupMenuItem(
                                  value: 'return_sale',
                                  child: Text('Return / Refund', style: TextStyle(color: Colors.orange)),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                              onSelected: (action) async {
                                if (action == 'details') {
                                  _showDetails(context, sale);
                                } else if (action == 'print_usb' ||
                                    action == 'print_bluetooth') {
                                  // Generate and print
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  final printLang =
                                      prefs.getString('print_language') ??
                                      'english';
                                  final useTamil =
                                      printLang == 'tamil' ||
                                      printLang == 'bilingual';

                                  Map<String, String>? tamilNames;
                                  if (useTamil) {
                                    tamilNames = {};
                                    for (final item in sale.items) {
                                      if (item.tamilName != null &&
                                          item.tamilName!.isNotEmpty) {
                                        tamilNames[item.productId] =
                                            item.tamilName!;
                                      }
                                    }
                                  }

                                  final profile = ref
                                      .read(profileProvider)
                                      .value;
                                  Logger.info(
                                    'SalesHistory: Generating receipt for sale ${sale.id}',
                                  );
                                  Logger.info(
                                    'SalesHistory: Items count: ${sale.items.length}',
                                  );
                                  Logger.info(
                                    'SalesHistory: Shop: ${profile?.shopName}',
                                  );
                                  final receiptData = ThermalInvoice.generate(
                                    sale: sale,
                                    shopName:
                                        profile?.shopName ?? 'IDEAL STORE',
                                    shopTagline: 'Smart Store - Smart Business',
                                    shopAddress: profile?.shopAddress,
                                    customerName: sale.customerName,
                                    useTamil: useTamil,
                                    tamilNames: tamilNames,
                                    shopNameTamil: profile?.shopName,
                                  );
                                  Logger.info(
                                    'SalesHistory: receiptData rows: ${receiptData.rows.length}',
                                  );

                                  if (action == 'print_usb') {
                                    Logger.info(
                                      'SalesHistory: Calling printStructured...',
                                    );
                                    final success =
                                        await ThermalPrinterService()
                                            .printStructured(
                                              receiptData,
                                              title: 'Quotation',
                                            );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? 'Printed successfully'
                                                : 'Print cancelled',
                                          ),
                                          backgroundColor: success
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      );
                                    }
                                  } else {
                                    // Bluetooth print
                                    final success =
                                        await ThermalPrinterService().printText(
                                          receiptData.toText(),
                                          hasTamil: useTamil,
                                        );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            success
                                                ? 'Sent to Bluetooth printer'
                                                : 'Bluetooth print failed',
                                          ),
                                          backgroundColor: success
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      );
                                    }
                                  }
                                } else if (action == 'share') {
                                  final profile = ref
                                      .read(profileProvider)
                                      .value;
                                  final pdfBytes = await _generatePdf(
                                    sale,
                                    profile?.shopName ?? 'IDEAL STORE',
                                    profile?.shopAddress,
                                  );
                                  if (pdfBytes != null && context.mounted) {
                                    final dir = await getTemporaryDirectory();
                                    final file = File(
                                      '${dir.path}/invoice_${sale.id.length >= 8 ? sale.id.substring(0, 8) : sale.id}.pdf',
                                    );
                                    await file.writeAsBytes(pdfBytes);
                                    await Share.shareXFiles([
                                      XFile(file.path),
                                    ], text: 'Invoice');
                                  }
                                } else if (action == 'edit') {
                                  // Load sale items into billing cart for editing
                                  if (widget.onEditSale != null)
                                    widget.onEditSale!(sale);
                                  final notifier = ref.read(
                                    desktopBillingProvider.notifier,
                                  );
                                  notifier.clearSession(
                                    notifier.activeSessionIndex,
                                  );
                                  for (final item in sale.items) {
                                    notifier.addItem(
                                      DesktopCartItem(
                                        productId: item.productId,
                                        name: item.name,
                                        price: item.price,
                                        qty: item.qty,
                                        unit: item.unit,
                                        purchasePrice: item.purchasePrice,
                                        gstRate: item.gstRate,
                                        hsnCode: item.hsnCode,
                                        tamilName: item.tamilName,
                                        discount: item.discount,
                                        unitType: item.unitType,
                                        piecesPerUnit: item.piecesPerUnit,
                                      ),
                                    );
                                  }
                                  if (sale.customerId != null &&
                                      sale.customerId!.isNotEmpty) {
                                    notifier.setCustomer(
                                      sale.customerId,
                                      sale.customerName,
                                    );
                                  }
                                  Navigator.pop(
                                    context,
                                  ); // Close sales history dialog
                                } else if (action == 'delete') {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Sale?'),
                                      content: const Text(
                                        'This will restore stock and reverse account entries. This action cannot be undone.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text(
                                            'Delete',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await ref
                                        .read(saleServiceProvider)
                                        .deleteSale(sale.id);
                                    ref.invalidate(salesHistoryProvider);
                                    ref.invalidate(productsProvider);
                                    _loadOfflineSales();
                                  }
                                } else if (action == 'return_sale') {
                                  _processReturn(sale);
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<Uint8List?> _generatePdf(
    Sale sale,
    String shopName,
    String? shopAddress,
  ) async {
    try {
      final pdf = pw.Document();
      final lines = ThermalInvoice.generate(
        sale: sale,
        shopName: shopName,
        shopAddress: shopAddress,
      ).toText().split('\n');

      final thermalWidth = PdfPageFormat.mm * 72;
      final thermalPage = PdfPageFormat(
        thermalWidth,
        PdfPageFormat.a5.height,
        marginBottom: 0,
        marginTop: 0,
        marginLeft: 0,
        marginRight: 0,
      );
      final font = pw.Font.courier();
      final fontBold = pw.Font.courierBold();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: thermalPage,
          build: (context) => [
            ...lines.map((line) {
              if (line.trim().startsWith('─') ||
                  line.trim().startsWith('-') ||
                  line.trim().startsWith('=')) {
                return pw.Divider();
              } else if (line == line.toUpperCase() && line.trim().length > 2) {
                return pw.Text(
                  line,
                  style: pw.TextStyle(font: fontBold, fontSize: 8),
                );
              } else {
                return pw.Text(
                  line,
                  style: pw.TextStyle(font: font, fontSize: 7),
                );
              }
            }),
          ],
        ),
      );

      return await pdf.save();
    } catch (e) {
      return null;
    }
  }

  void _processReturn(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Process Return?'),
        content: Text(
          'Return entire sale #${sale.id.length >= 8 ? sale.id.substring(0, 8) : sale.id}?\n\n'
          'Amount: Rs${sale.finalAmount.toStringAsFixed(2)}\n'
          'This will restore stock for all ${sale.items.length} items.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Return Full Sale'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(saleServiceProvider).deleteSale(sale.id);
      ref.invalidate(salesHistoryProvider);
      ref.invalidate(productsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Return processed — Rs${sale.finalAmount.toStringAsFixed(2)} refunded, stock restored'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Return failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDetails(BuildContext context, Sale sale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sale Details'),
        content: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('Date: ${AppTimezone.formatDateTime(sale.createdAt)}'),
              Text('Payment: ${sale.paymentMethod.toUpperCase()}'),
              if (sale.customerName != null && sale.customerName!.isNotEmpty)
                Text('Customer: ${sale.customerName}'),
              const Divider(),
              ...sale.items.map(
                (item) => ListTile(
                  dense: true,
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.qty} × Rs${item.price.toStringAsFixed(2)}',
                  ),
                  trailing: Text('Rs${item.total.toStringAsFixed(2)}'),
                ),
              ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'TOTAL: Rs${sale.finalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
