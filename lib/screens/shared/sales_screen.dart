import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../utils/logger.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/sale.dart';
import '../../models/product.dart';
import '../../config/app_colors.dart';
import '../../config/providers.dart';
import '../../services/email_service.dart';
import '../../services/return_service.dart';
import '../../services/sale_service.dart';
import '../../utils/invoice_generator.dart';
import '../../utils/thermal_invoice.dart';
import '../../services/thermal_printer_service.dart';
import '../../utils/app_timezone.dart';
import '../../widgets/empty_state.dart';
import 'cart_screen.dart';
import 'product_form_screen.dart';

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesHistoryProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sales'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'New Sale'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const CartScreen(),
            _SalesHistory(salesAsync: salesAsync),
          ],
        ),
      ),
    );
  }
}

class _SalesHistory extends ConsumerStatefulWidget {
  final AsyncValue<List<Sale>> salesAsync;

  const _SalesHistory({required this.salesAsync});

  @override
  ConsumerState<_SalesHistory> createState() => _SalesHistoryState();
}

class _SalesHistoryState extends ConsumerState<_SalesHistory> {
  Set<String> _paymentFilters = {};
  Set<String> _statusFilters = {};
  String _dateFilter = 'all';
  String _searchQuery = '';

  String _generateInvoiceText(Sale sale) {
    final profile = ref.read(profileProvider).value;
    return ThermalInvoice.generate(
      sale: sale,
      shopName: profile?.shopName ?? 'IDEAL STORE',
      shopTagline: 'Smart Store - Smart Business',
      shopAddress: profile?.shopAddress,
      gstin: profile?.gstin,
    ).toText();
  }

  Future<void> _shareWhatsApp(
    BuildContext context,
    WidgetRef ref,
    Sale sale,
  ) async {
    try {
      final text = _generateInvoiceText(sale);
      await Share.share(text);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(salesHistoryProvider),
      child: widget.salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sales) {
          if (sales.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long,
              title: 'No Sales Yet',
              subtitle: 'Sales will appear here after your first transaction',
            );
          }

          // Apply filters
          var filtered = sales.where((s) {
            // Payment method filter
            if (_paymentFilters.isNotEmpty && !_paymentFilters.contains(s.paymentMethod)) return false;
            // Status filter
            if (_statusFilters.contains('credit') && !s.isCredit) return false;
            if (_statusFilters.contains('paid') && s.isCredit) return false;
            // Date filter
            final now = DateTime.now();
            if (_dateFilter == 'today') {
              if (s.createdAt.day != now.day || s.createdAt.month != now.month || s.createdAt.year != now.year) return false;
            } else if (_dateFilter == '7d') {
              if (now.difference(s.createdAt).inDays > 7) return false;
            } else if (_dateFilter == '30d') {
              if (now.difference(s.createdAt).inDays > 30) return false;
            }
            // Search
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final matchesName = s.customerName?.toLowerCase().contains(q) == true;
              final matchesAmt = s.finalAmount.toString().contains(q);
              if (!matchesName && !matchesAmt) return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by customer or amount...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              // Payment method chips
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  children: [
                    _buildSalesFilterChip('All', '', _paymentFilters, () => setState(() => _paymentFilters.clear())),
                    _buildSalesFilterChip('Cash', 'cash', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('cash'); })),
                    _buildSalesFilterChip('Credit', 'credit', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('credit'); })),
                    _buildSalesFilterChip('Digital', 'digital', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('digital'); })),
                    _buildSalesFilterChip('UPI', 'upi', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('upi'); })),
                    _buildSalesFilterChip('Split', 'split', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('split'); })),
                  ],
                ),
              ),
              // Status + Date chips
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  children: [
                    _buildStatusChip('Paid', 'paid'),
                    _buildStatusChip('Credit Due', 'credit'),
                    const SizedBox(width: 8),
                    _buildDateChip('All', 'all'),
                    _buildDateChip('Today', 'today'),
                    _buildDateChip('7 Days', '7d'),
                    _buildDateChip('30 Days', '30d'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // Count
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${filtered.length} sales', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
              ),
              const SizedBox(height: 4),
              // Export button
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exportSalesPdf(context, filtered),
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        label: const Text('Export PDF'),
                      ),
                    ),
                  ],
                ),
              ),
              // Sales list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final sale = filtered[index];
                    final paymentColor = AppColors.getPaymentColor(
                      sale.paymentMethod,
                    );
                    return Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: paymentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            sale.paymentMethod == 'cash'
                                ? Icons.money
                                : sale.paymentMethod == 'credit'
                                ? Icons.credit_card
                                : Icons.phone_android,
                            color: paymentColor,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              'Rs${sale.finalAmount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ReturnsBadge(saleId: sale.id),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: paymentColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                sale.paymentMethod.toUpperCase(),
                                style: TextStyle(
                                  color: paymentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${sale.customerName ?? "Walk-in"} | ${sale.items.length} items | ${AppTimezone.formatDateTime(sale.createdAt)}',
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'edit_sale',
                              child: Text('Edit Sale'),
                            ),
                            const PopupMenuItem(
                              value: 'bluetooth_print',
                              child: Text('Print (Bluetooth)'),
                            ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Text('Share PDF Invoice'),
                            ),
                            const PopupMenuItem(
                              value: 'thermal_share',
                              child: Text('Share Text Invoice'),
                            ),
                            const PopupMenuItem(
                              value: 'whatsapp',
                              child: Text('Share on WhatsApp'),
                            ),
                            const PopupMenuItem(
                              value: 'email',
                              child: Text('Email Invoice'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                          onSelected: (value) async {
                            if (value == 'edit_sale') {
                              _editSale(context, ref, sale);
                            } else if (value == 'bluetooth_print') {
                              final thermalService = ThermalPrinterService();
                              final isConfigured = await thermalService
                                  .isConfigured();
                              if (isConfigured) {
                                final profile = ref.read(profileProvider).value;
                                // Fetch customer name if available
                                String? custName;
                                if (sale.customerId != null) {
                                  try {
                                    final custRes = await Supabase
                                        .instance
                                        .client
                                        .from('customers')
                                        .select('name')
                                        .eq('id', sale.customerId!)
                                        .maybeSingle();
                              custName = custRes?['name'] as String?;
                            } catch (e) {
                              Logger.warning('Failed to fetch customer name for A4 receipt: $e');
                            }
                          }
                          final receiptData = ThermalInvoice.generate(
                                  sale: sale,
                                  shopName: profile?.shopName ?? 'IDEAL STORE',
                                  shopTagline: 'Smart Store - Smart Business',
                                  shopAddress: profile?.shopAddress,
                                  customerName: custName,
                                  gstin: profile?.gstin,
                                );
                                final prefs =
                                    await SharedPreferences.getInstance();
                                final printLang =
                                    prefs.getString('print_language') ??
                                    'english';
                                final useTamilBT =
                                    printLang == 'tamil' ||
                                    printLang == 'bilingual';
                                final success = await thermalService.printText(
                                  receiptData.toText(),
                                  hasTamil: useTamilBT,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        success ? 'Printed!' : 'Print failed',
                                      ),
                                      backgroundColor: success
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  );
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No printer configured. Go to More → Printer Setup',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              }
                            } else if (value == 'share') {
                              final profile = ref.read(profileProvider).value;
                              await InvoiceGenerator.shareInvoice(
                                sale,
                                shopName: profile?.shopName,
                                shopAddress: profile?.shopAddress,
                              );
                            } else if (value == 'thermal_share') {
                              final thermalService = ThermalPrinterService();
                              final profile = ref.read(profileProvider).value;
                              // Fetch customer name if available
                              String? custName;
                              if (sale.customerId != null) {
                                try {
                                  final custRes = await Supabase.instance.client
                                      .from('customers')
                                      .select('name')
                                      .eq('id', sale.customerId!)
                                      .maybeSingle();
                                  custName = custRes?['name'] as String?;
                                } catch (e) {
                                  Logger.warning('Failed to fetch customer name for thermal receipt: $e');
                                }
                              }
                              final receiptData = ThermalInvoice.generate(
                                sale: sale,
                                shopName: profile?.shopName ?? 'IDEAL STORE',
                                shopTagline: 'Smart Store - Smart Business',
                                shopAddress: profile?.shopAddress,
                                customerName: custName,
                                gstin: profile?.gstin,
                              );
                              await thermalService.shareAsTextFile(
                                receiptData.toText(),
                                fileName: 'invoice_${sale.id.length >= 8 ? sale.id.substring(0, 8) : sale.id}',
                              );
                            } else if (value == 'whatsapp') {
                              await _shareWhatsApp(context, ref, sale);
                            } else if (value == 'email') {
                              _showEmailDialog(context, ref, sale);
                            } else if (value == 'delete') {
                              _confirmDelete(context, ref, sale);
                            }
                          },
                        ),
                        onTap: () => _showSaleDetails(context, ref, sale),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportSalesPdf(BuildContext context, List<Sale> sales) async {
    try {
      final pdf = pw.Document();
      double totalAll = 0;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'SALES HISTORY',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Generated: ${AppTimezone.formatDateTime(DateTime.now())}'),
            pw.Text('Total Sales: ${sales.length}'),
            pw.SizedBox(height: 16),

            // Each sale as a separate section
            ...sales
                .asMap()
                .entries
                .map((entry) {
                  final i = entry.key + 1;
                  final s = entry.value;
                  totalAll += s.finalAmount;

                  return [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Sale #$i',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(AppTimezone.formatDateTime(s.createdAt)),
                          pw.Text(
                            'Rs${s.finalAmount.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    pw.Text(
                      'Payment: ${s.paymentMethod.toUpperCase()} | Status: ${s.isCredit ? "Credit" : "Paid"}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 4),

                    // Items table
                    pw.TableHelper.fromTextArray(
                      headerStyle: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8,
                      ),
                      cellStyle: const pw.TextStyle(fontSize: 8),
                      headerDecoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      cellHeight: 18,
                      headers: ['Product', 'Qty', 'Price', 'Total'],
                      data: s.items
                          .map(
                            (item) => [
                              item.name,
                              '${item.qty}',
                              'Rs${item.price.toStringAsFixed(2)}',
                              'Rs${item.total.toStringAsFixed(2)}',
                            ],
                          )
                          .toList(),
                    ),
                    pw.SizedBox(height: 8),
                  ];
                })
                .expand((e) => e),

            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Grand Total: Rs${totalAll.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'Sales_History.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editSale(BuildContext context, WidgetRef ref, Sale sale) async {
    final editedItems = sale.items
        .map(
          (item) => CartItem(
            productId: item.productId,
            name: item.name,
            price: item.price,
            qty: item.qty,
            unit: item.unit,
            purchasePrice: item.purchasePrice,
            gstRate: item.gstRate,
            hsnCode: item.hsnCode,
            discount: item.discount,
          ),
        )
        .toList();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EditSaleDialog(sale: sale, items: editedItems),
    );

    if (result == null || !context.mounted) return;

    final newItems = result['items'] as List<CartItem>;
    final newTotal = result['total'] as double;
    final reason = (result['reason'] as String?)?.trim() ?? '';
    final billDiscount = sale.discount;
    final finalAmount = (newTotal - billDiscount).clamp(0.0, double.infinity);
    final isCredit = sale.isCredit;
    final amountPaid = isCredit
        ? sale.amountPaid.clamp(0.0, finalAmount)
        : finalAmount;
    final dueAmount = isCredit ? (finalAmount - amountPaid) : 0.0;

    double cashAmount = sale.cashAmount;
    double digitalAmount = sale.digitalAmount;
    if (!isCredit) {
      final method = sale.paymentMethod;
      if (method == 'split') {
        final oldPaid = (sale.cashAmount + sale.digitalAmount);
        if (oldPaid > 0) {
          cashAmount = finalAmount * (sale.cashAmount / oldPaid);
          digitalAmount = finalAmount - cashAmount;
        } else {
          cashAmount = finalAmount;
          digitalAmount = 0;
        }
      } else if (method == 'digital' || method == 'upi' || method == 'bank') {
        cashAmount = 0;
        digitalAmount = finalAmount;
      } else {
        cashAmount = finalAmount;
        digitalAmount = 0;
      }
    } else {
      cashAmount = 0;
      digitalAmount = 0;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Changes?'),
        content: Text(
          'Original: Rs${sale.finalAmount.toStringAsFixed(0)}\n'
          'New: Rs${finalAmount.toStringAsFixed(0)}\n\n'
          'Stock and accounts will be adjusted safely.\n'
          'Reason: $reason',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      await SaleService().editSaleAtomic(
        saleId: sale.id,
        items: newItems,
        totalAmount: newTotal,
        discount: billDiscount,
        finalAmount: finalAmount,
        customerId: sale.customerId,
        isCredit: isCredit,
        amountPaid: amountPaid,
        dueAmount: dueAmount,
        paymentMethod: sale.paymentMethod,
        cashAmount: cashAmount,
        digitalAmount: digitalAmount,
        reason: reason,
      );

      ref.invalidate(salesHistoryProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(accountsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _editProductFromSale(
    BuildContext context,
    WidgetRef ref,
    String productId,
  ) async {
    try {
      final product = await ref
          .read(productServiceProvider)
          .getProductById(productId);
      if (product != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductFormScreen(product: product),
          ),
        ).then((_) => ref.invalidate(salesHistoryProvider));
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product not found'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEmailDialog(BuildContext context, WidgetRef ref, Sale sale) {
    final emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Email Invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter customer email to send invoice:'),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Enter valid email'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              await _sendEmailInvoice(context, ref, sale, email);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendEmailInvoice(
    BuildContext context,
    WidgetRef ref,
    Sale sale,
    String email,
  ) async {
    try {
      final profile = ref.read(profileProvider).value;
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a5,
          build: (context) => [
            InvoiceGenerator.buildInvoice(
              sale,
              shopName: profile?.shopName,
              shopAddress: profile?.shopAddress,
            ),
          ],
        ),
      );
      final pdfBytes = await pdf.save();

      final emailService = EmailService();
      await emailService.sendInvoiceEmail(
        context: context,
        toEmail: email,
        sale: sale,
        pdfBytes: pdfBytes,
        shopName: 'IDEAL STORE',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate/send email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Sale sale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sale'),
        content: Text(
          'Delete sale of Rs${sale.finalAmount.toStringAsFixed(0)}? Stock will be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(saleServiceProvider).deleteSale(sale.id);
                ref.invalidate(salesHistoryProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Sale deleted'),
                      backgroundColor: Colors.green,
                      action: SnackBarAction(
                        label: 'Undo',
                        textColor: Colors.white,
                        onPressed: () {
                          // Note: Undo would require re-creating the sale
                          // For now, just show message
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Undo not available - create sale manually',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSaleDetails(BuildContext context, WidgetRef ref, Sale sale) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sale Details',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(AppTimezone.formatDateTime(sale.createdAt)),
              if (sale.customerName != null && sale.customerName!.isNotEmpty)
                Text(
                  'Customer: ${sale.customerName}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              const Divider(),
              ...sale.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.name} x${item.qty}'),
                            if (item.discount > 0)
                              Text(
                                'Rs${item.total.toStringAsFixed(2)} (-${item.discount.toStringAsFixed(0)}%)',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                ),
                              ),
                            if (item.discount <= 0)
                              Text(
                                'Rs${item.total.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.blue,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _editProductFromSale(context, ref, item.productId);
                        },
                        tooltip: 'Edit Product',
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal:'),
                  Text('Rs${sale.totalAmount.toStringAsFixed(2)}'),
                ],
              ),
              if (sale.totalDiscount > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Item Discounts:'),
                    Text(
                      '-Rs${sale.totalDiscount.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ),
              if (sale.discount > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Bill Discount:'),
                    Text('-Rs${sale.discount.toStringAsFixed(2)}'),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Rs${sale.finalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSalesFilterChip(String label, String value, Set<String> selected, VoidCallback onTap) {
    final isSelected = value.isEmpty ? selected.isEmpty : selected.contains(value);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: const Color(0xFF667eea),
        backgroundColor: Colors.grey.shade100,
        checkmarkColor: Colors.white,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value) {
    final isSelected = _statusFilters.contains(value);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: Colors.orange,
        backgroundColor: Colors.grey.shade100,
        checkmarkColor: Colors.white,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() {
          if (isSelected) {
            _statusFilters.remove(value);
          } else {
            _statusFilters.add(value);
          }
        }),
      ),
    );
  }

  Widget _buildDateChip(String label, String value) {
    final isSelected = _dateFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: Colors.teal,
        backgroundColor: Colors.grey.shade100,
        checkmarkColor: Colors.white,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _dateFilter = value),
      ),
    );
  }
}

class _ReturnsBadge extends ConsumerWidget {
  final String saleId;

  const _ReturnsBadge({required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List>(
      future: ReturnService().getReturnsBySaleId(saleId),
      builder: (context, snapshot) {
        if (!snapshot.hasData ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final returnCount = snapshot.data!.length;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$returnCount return${returnCount > 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 10,
              color: Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}

class _EditSaleDialog extends StatefulWidget {
  final Sale sale;
  final List<CartItem> items;

  const _EditSaleDialog({required this.sale, required this.items});

  @override
  State<_EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends State<_EditSaleDialog> {
  late List<CartItem> _items;
  List<Product> _allProducts = [];
  final _reasonController = TextEditingController();

  double _effectivePurchasePrice(Product product) {
    if (product.purchasePrice > 0) return product.purchasePrice;
    if (product.variants.isNotEmpty) return product.variants.first.purchasePrice;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    _loadProducts();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final response = await Supabase.instance.client
          .from('products')
          .select(
            'id, name, selling_price, purchase_price, stock, unit, gst_rate, hsn_code',
          )
          .order('name');
      if (mounted) {
        setState(() {
          _allProducts = (response as List)
              .map((e) => Product.fromJson(e))
              .toList();
        });
      }
    } catch (e) {
      Logger.warning('Failed to load products for sales screen: $e');
    }
  }

  double get _total => _items.fold(0.0, (sum, item) => sum + item.total);

  void _updateQty(int index, int delta) {
    setState(() {
      final newQty = _items[index].qty + delta;
      if (newQty <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].qty = newQty;
      }
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _editPrice(int index) {
    final item = _items[index];
    final controller = TextEditingController(
      text: item.price.toStringAsFixed(2),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Edit Price - ${item.name}',
          style: const TextStyle(fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'New Price',
            prefixText: 'Rs ',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newPrice = double.tryParse(controller.text);
              if (newPrice != null && newPrice > 0) {
                setState(
                  () => _items[index] = CartItem(
                    productId: item.productId,
                    name: item.name,
                    price: newPrice,
                    qty: item.qty,
                    unit: item.unit,
                    purchasePrice: item.purchasePrice,
                    gstRate: item.gstRate,
                    hsnCode: item.hsnCode,
                    discount: item.discount,
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _editQty(int index) {
    final item = _items[index];
    final controller = TextEditingController(text: item.qty.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Edit Qty - ${item.name}',
          style: const TextStyle(fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'New Qty'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newQty = int.tryParse(controller.text);
              if (newQty != null && newQty > 0) {
                setState(
                  () => _items[index] = CartItem(
                    productId: item.productId,
                    name: item.name,
                    price: item.price,
                    qty: newQty,
                    unit: item.unit,
                    purchasePrice: item.purchasePrice,
                    gstRate: item.gstRate,
                    hsnCode: item.hsnCode,
                    discount: item.discount,
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _addProduct() {
    final searchController = TextEditingController();
    List<Product> filtered = List.from(_allProducts);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search product...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  onChanged: (v) {
                    setSheetState(() {
                      filtered = _allProducts
                          .where(
                            (p) =>
                                p.name.toLowerCase().contains(
                                  v.toLowerCase(),
                                ) ||
                                (p.tamilName?.toLowerCase().contains(
                                      v.toLowerCase(),
                                    ) ??
                                    false),
                          )
                          .toList();
                    });
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final product = filtered[index];
                    return ListTile(
                      title: Text(product.name),
                      subtitle: Text(
                        'Rs${product.sellingPrice} | Stock: ${product.stock}',
                      ),
                      trailing: const Icon(
                        Icons.add_circle,
                        color: Colors.green,
                      ),
                      onTap: () {
                        setState(() {
                          final existing = _items.indexWhere(
                            (i) => i.productId == product.id,
                          );
                          if (existing >= 0) {
                            _items[existing].qty += 1;
                          } else {
                            _items.add(
                              CartItem(
                                productId: product.id,
                                name: product.name,
                                price: product.sellingPrice,
                                qty: 1,
                                unit: product.unit,
                                purchasePrice: _effectivePurchasePrice(product),
                                gstRate: product.gstRate,
                                hsnCode: product.hsnCode,
                              ),
                            );
                          }
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Text(
            'Edit Sale - Rs${widget.sale.finalAmount.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Summary bar
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    '${_items.length} items',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    'Total: Rs${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    onPressed: _addProduct,
                    tooltip: 'Add Product',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Items list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          // Product name
                          Expanded(
                            flex: 3,
                            child: Text(
                              item.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          // Qty with edit
                          GestureDetector(
                            onTap: () => _editQty(index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => _updateQty(index, -1),
                                    child: const Icon(Icons.remove, size: 14),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      '${item.qty}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _updateQty(index, 1),
                                    child: const Icon(Icons.add, size: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Price with edit
                          GestureDetector(
                            onTap: () => _editPrice(index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Rs${item.price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Total
                          Text(
                            'Rs${item.total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          // Delete
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.red,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
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
            // Reason field
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for edit *',
                hintText: 'e.g. Wrong qty entered',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (reason.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit reason is required')),
              );
              return;
            }
            if (_items.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add at least one item')),
              );
              return;
            }
            Navigator.pop(context, {
              'items': _items,
              'total': _total,
              'reason': reason,
            });
          },
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Save Changes'),
        ),
      ],
    );
  }
}
