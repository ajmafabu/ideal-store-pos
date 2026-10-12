import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/providers.dart';
import '../../../config/desktop_billing_provider.dart';
import '../../../models/sale.dart';
import '../../../services/offline_service.dart';
import '../../../services/thermal_printer_service.dart';
import '../../../utils/app_timezone.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/logger.dart';
import '../../../utils/thermal_invoice.dart';
import '../../../utils/qty_format.dart';

String _rs(double v, {int decimals = 2}) => '₹${v.toStringAsFixed(decimals)}';

class DesktopSalesHistoryDialog extends ConsumerStatefulWidget {
  final Function(Sale)? onEditSale;
  final DesktopBillingNotifier? notifier;
  const DesktopSalesHistoryDialog({super.key, this.onEditSale, this.notifier});

  @override
  ConsumerState<DesktopSalesHistoryDialog> createState() =>
      _DesktopSalesHistoryDialogState();
}

class _DesktopSalesHistoryDialogState
    extends ConsumerState<DesktopSalesHistoryDialog> {
  final _searchController = TextEditingController();
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _onSearchKey);
  final _listController = ScrollController();
  String _query = '';
  List<Sale> _offlineSales = [];
  bool _loadedOffline = false;
  int _highlight = 0;
  List<Sale> _visible = const [];

  /// sale id → amount returned so far (from product_returns)
  Map<String, double> _returned = {};

  static const _rowHeight = 64.0;

  @override
  void initState() {
    super.initState();
    _loadOfflineSales();
    _loadReturns();
    // The list used to open with yesterday's cached bills and an "OFFLINE"
    // badge until refresh was pressed (QA 12 Oct). Fetch fresh on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(salesHistoryProvider);
    });
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

  /// A returned bill kept showing "PAID" with no sign of the return.
  Future<void> _loadReturns() async {
    try {
      final rows = await Supabase.instance.client
          .from('product_returns')
          .select('sale_id, return_amount, refund_amount')
          .order('created_at', ascending: false)
          .limit(3000);
      final map = <String, double>{};
      for (final r in rows as List) {
        final id = r['sale_id'] as String?;
        if (id == null) continue;
        final amount = (r['return_amount'] as num?)?.toDouble() ??
            (r['refund_amount'] as num?)?.toDouble() ??
            0;
        map[id] = (map[id] ?? 0) + amount;
      }
      if (mounted) setState(() => _returned = map);
    } catch (e) {
      Logger.warning('Sales history: returns not loaded: $e');
    }
  }

  void _refresh() {
    ref.invalidate(salesHistoryProvider);
    ref.invalidate(productsProvider);
    _loadOfflineSales();
    _loadReturns();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _listController.dispose();
    super.dispose();
  }

  /// Bill number, customer, amount, payment or a product on the bill.
  List<Sale> _filter(List<Sale> sales) {
    if (_query.isEmpty) return sales;
    final q = _query.toLowerCase().replaceAll('#', '');
    return sales.where((s) {
      if (s.invoiceLabel.toLowerCase() == q) return true;
      if ((s.invoiceNo?.toString() ?? '').startsWith(q)) return true;
      if (s.finalAmount.toStringAsFixed(0).contains(q)) return true;
      if ((s.customerName ?? 'walk-in').toLowerCase().contains(q)) return true;
      if (s.paymentMethod.toLowerCase().contains(q)) return true;
      return s.items.any((i) =>
          i.name.toLowerCase().contains(q) ||
          (i.tamilName ?? '').toLowerCase().contains(q));
    }).toList();
  }

  // ── keyboard: ↑ ↓ pick a bill, Enter details, Ctrl+P/E/R, Ctrl+Delete ──
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (_visible.isEmpty) return KeyEventResult.ignored;
    final sale = _visible[_highlight.clamp(0, _visible.length - 1)];
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _showDetails(context, sale);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyP) {
      _print(sale);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyE) {
      _edit(sale);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyR) {
      _processReturn(sale);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.delete) {
      _delete(sale);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveHighlight(int step) {
    if (_visible.isEmpty) return;
    setState(() => _highlight = (_highlight + step).clamp(0, _visible.length - 1));
    if (!_listController.hasClients) return;
    final top = _highlight * _rowHeight;
    final view = _listController.position.viewportDimension;
    final offset = _listController.offset;
    if (top < offset) {
      _listController.jumpTo(top);
    } else if (top + _rowHeight > offset + view) {
      _listController.jumpTo(top + _rowHeight - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesHistoryProvider);

    // Merge: online provider data + offline Hive data (always fresh from Hive)
    final List<Sale> displaySales;
    final onlineSales = salesAsync.hasValue ? salesAsync.value : null;
    if (onlineSales != null && onlineSales.isNotEmpty) {
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
    _visible = _filter(displaySales);
    if (_highlight >= _visible.length) _highlight = 0;

    return AlertDialog(
      title: Row(
        children: [
          const Text('Sales History'),
          const Spacer(),
          if (salesAsync.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          // "OFFLINE" only when the server really could not be reached
          if (salesAsync.hasError && _loadedOffline)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('OFFLINE', style: TextStyle(fontSize: 10, color: Color(0xFFC2410C))),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _refresh,
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by bill no, customer, product, amount, payment...',
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
                            _highlight = 0;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() {
                _query = v.trim();
                _highlight = 0;
              }),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                '↑ ↓ choose bill  ·  Enter details  ·  Ctrl+P print  ·  Ctrl+E edit  ·  Ctrl+R return  ·  Ctrl+Del delete  ·  Esc close',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ),
            Expanded(
              child: displaySales.isEmpty
                  ? Center(
                      child: Text(
                        salesAsync.isLoading ? 'Loading...' : 'No sales yet',
                      ),
                    )
                  : _visible.isEmpty
                      ? const Center(child: Text('No results found'))
                      : ListView.builder(
                          controller: _listController,
                          itemExtent: _rowHeight,
                          itemCount: _visible.length,
                          itemBuilder: (context, index) =>
                              _saleRow(_visible[index], index == _highlight),
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

  Widget _saleRow(Sale sale, bool highlighted) {
    final returned = _returned[sale.id] ?? 0;
    final fullyReturned = returned > 0 && returned >= sale.finalAmount - 0.5;
    final bool isPaid = !sale.isCredit || sale.dueAmount <= 0;

    final (String badge, Color fg, Color bg) = fullyReturned
        ? ('RETURNED', const Color(0xFFC2410C), Colors.orange.shade50)
        : returned > 0
            ? ('RETURNED ${_rs(returned, decimals: 0)}', const Color(0xFFC2410C), Colors.orange.shade50)
            : isPaid
                ? ('PAID', const Color(0xFF2E7D32), Colors.green.shade50)
                : ('DUE: ${_rs(sale.dueAmount, decimals: 0)}', Colors.red.shade700, Colors.red.shade50);

    return Container(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFE0F2FE) : null,
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _showDetails(context, sale),
        title: Text.rich(
          TextSpan(children: [
            TextSpan(
              text: '#${sale.invoiceLabel}   ',
              style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: _rs(sale.finalAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: fullyReturned ? TextDecoration.lineThrough : null,
              ),
            ),
          ]),
        ),
        subtitle: Text(
          '${sale.customerName ?? "Walk-in"} | ${sale.items.length} products | ${sale.paymentMethod.toUpperCase()} | ${AppTimezone.formatDateTime(sale.createdAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: fg.withValues(alpha: 0.4)),
              ),
              child: Text(
                badge,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
              ),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'details', child: Text('View Details   (Enter)')),
                const PopupMenuItem(value: 'print_usb', child: Text('Print   (Ctrl+P)')),
                // Bluetooth printing is the phone's; on Windows it did nothing
                if (!Platform.isWindows)
                  const PopupMenuItem(value: 'print_bluetooth', child: Text('Print (Bluetooth)')),
                const PopupMenuItem(value: 'share', child: Text('Share PDF')),
                const PopupMenuItem(value: 'edit', child: Text('Edit Sale   (Ctrl+E)')),
                const PopupMenuItem(
                  value: 'return_sale',
                  child: Text('Return / Refund   (Ctrl+R)', style: TextStyle(color: Color(0xFFC2410C))),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete   (Ctrl+Del)', style: TextStyle(color: Color(0xFFC62828))),
                ),
              ],
              onSelected: (action) {
                switch (action) {
                  case 'details':
                    _showDetails(context, sale);
                  case 'print_usb':
                    _print(sale);
                  case 'print_bluetooth':
                    _print(sale, bluetooth: true);
                  case 'share':
                    _share(sale);
                  case 'edit':
                    _edit(sale);
                  case 'delete':
                    _delete(sale);
                  case 'return_sale':
                    _processReturn(sale);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  Future<void> _print(Sale sale, {bool bluetooth = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final printLang = prefs.getString('print_language') ?? 'english';
    final useTamil = printLang == 'tamil' || printLang == 'bilingual';

    Map<String, String>? tamilNames;
    if (useTamil) {
      tamilNames = {};
      for (final item in sale.items) {
        if (item.tamilName != null && item.tamilName!.isNotEmpty) {
          tamilNames[item.productId] = item.tamilName!;
        }
      }
    }

    final profile = ref.read(profileProvider).value;
    Logger.info('SalesHistory: printing sale ${sale.id}');
    final receiptData = ThermalInvoice.generate(
      sale: sale,
      shopName: profile?.shopName ?? 'IDEAL STORE',
      shopTagline: 'Smart Store - Smart Business',
      shopAddress: profile?.shopAddress,
      customerName: sale.customerName,
      useTamil: useTamil,
      tamilNames: tamilNames,
      shopNameTamil: profile?.shopName,
    );

    if (!bluetooth) {
      final success = await ThermalPrinterService().printStructured(receiptData, title: 'Quotation');
      _toast(success ? 'Printed bill #${sale.invoiceLabel}' : 'Print cancelled',
          success ? Colors.green : Colors.orange);
    } else {
      final success = await ThermalPrinterService().printText(receiptData.toText(), hasTamil: useTamil);
      _toast(success ? 'Sent to Bluetooth printer' : 'Bluetooth print failed',
          success ? Colors.green : Colors.orange);
    }
    _searchFocus.requestFocus();
  }

  Future<void> _share(Sale sale) async {
    final profile = ref.read(profileProvider).value;
    final pdfBytes = await _generatePdf(
      sale,
      profile?.shopName ?? 'IDEAL STORE',
      profile?.shopAddress,
    );
    if (pdfBytes == null || !mounted) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/invoice_${sale.invoiceLabel}.pdf');
    await file.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Invoice');
  }

  void _edit(Sale sale) {
    // the parent holds the current bill and loads this one
    widget.onEditSale?.call(sale);
    Navigator.pop(context);
  }

  /// Deleting a bill took one click with no name on it (QA 12 Oct): name the
  /// bill. No PIN here — the owner asked for no PIN locks on Windows (13 Oct).
  Future<void> _delete(Sale sale) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete bill #${sale.invoiceLabel}?'),
        content: Text(
          '${_rs(sale.finalAmount)} · ${sale.customerName ?? 'Walk-in'} · '
          '${AppTimezone.formatDateTime(sale.createdAt)}\n\n'
          'Stock goes back and the money entries are reversed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            autofocus: true, // Enter on its own cancels; deleting takes a click or Tab
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFC62828))),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      _searchFocus.requestFocus();
      return;
    }
    try {
      await ref.read(saleServiceProvider).deleteSale(sale.id);
      _refresh();
      _toast('Bill #${sale.invoiceLabel} deleted', Colors.green);
    } catch (e) {
      _toast('Delete failed: ${ErrorMessages.parse(e)}', Colors.red);
    }
    _searchFocus.requestFocus();
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

  Future<void> _processReturn(Sale sale) async {
    final returned = _returned[sale.id] ?? 0;
    if (returned >= sale.finalAmount - 0.5 && returned > 0) {
      // said "Return recorded for 0 line(s) — stock restored" before
      _toast('Bill #${sale.invoiceLabel} is already fully returned', Colors.orange);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Return bill #${sale.invoiceLabel}?'),
        content: Text(
          'Return everything left on this bill?\n\n'
          'Amount: ${_rs(sale.finalAmount)}'
          '${returned > 0 ? ' (already returned ${_rs(returned)})' : ''}\n'
          'Stock goes back, the customer\'s due is reduced and any refund is paid the way the bill was paid.\n\n'
          'To return only some items, use Returns in the menu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Return Full Sale'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      _searchFocus.requestFocus();
      return;
    }

    try {
      // proper return records instead of deleting the sale (#14)
      final lines = await ref.read(saleServiceProvider).returnFullSale(sale.id);
      ref.invalidate(returnsProvider);
      _refresh();
      _toast(
        lines > 0
            ? 'Bill #${sale.invoiceLabel}: $lines line(s) returned — stock restored'
            : 'Nothing left to return on bill #${sale.invoiceLabel}',
        Colors.orange,
      );
    } catch (e) {
      _toast('Return failed: ${ErrorMessages.parse(e)}', Colors.red);
    }
    _searchFocus.requestFocus();
  }

  /// Everything on the bill: discount, extra charges, how it was paid and
  /// what is still due (only the items and the total were shown).
  void _showDetails(BuildContext context, Sale sale) {
    final returned = _returned[sale.id] ?? 0;
    final itemsTotal = sale.items.fold<double>(0, (s, i) => s + i.total);
    Widget line(String label, String value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: color))),
              Text(value,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
            ],
          ),
        );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bill #${sale.invoiceLabel}'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('Date: ${AppTimezone.formatDateTime(sale.createdAt)}'),
              Text('Customer: ${sale.customerName?.isNotEmpty == true ? sale.customerName : 'Walk-in'}'),
              Text('Payment: ${sale.paymentMethod.toUpperCase()}'),
              const Divider(),
              ...sale.items.map(
                (item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: Text('${formatQty(item.qty)} × ${_rs(item.price)}'),
                  trailing: Text(_rs(item.total)),
                ),
              ),
              const Divider(),
              line('Items', _rs(itemsTotal)),
              if (sale.discount > 0) line('Bill discount', '− ${_rs(sale.discount)}'),
              if (sale.extraCharges > 0) line('Extra charges', '+ ${_rs(sale.extraCharges)}'),
              if (sale.roundOff.abs() >= 0.01)
                line('Round off', '${sale.roundOff >= 0 ? '+' : '−'} ${_rs(sale.roundOff.abs())}'),
              line('TOTAL', _rs(sale.finalAmount), bold: true),
              const Divider(),
              if (sale.cashAmount > 0) line('Paid cash', _rs(sale.cashAmount)),
              if (sale.digitalAmount > 0) line('Paid UPI / bank', _rs(sale.digitalAmount)),
              if (sale.dueAmount > 0)
                line('Due (on credit)', _rs(sale.dueAmount), bold: true, color: Colors.red.shade700),
              if (returned > 0)
                line('Returned', _rs(returned), bold: true, color: const Color(0xFFC2410C)),
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
    ).then((_) => _searchFocus.requestFocus());
  }
}
