import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../utils/app_timezone.dart';
import '../utils/tamil_bitmap_renderer.dart';

/// Output from ThermalInvoice: structured data for the renderer.
class ThermalReceiptData {
  final List<String> headerLines;
  final List<ThermalRow> rows;
  final List<String> totalLines;
  final List<String> footerLines;

  const ThermalReceiptData({
    required this.headerLines,
    required this.rows,
    required this.totalLines,
    required this.footerLines,
  });

  /// Convert back to plain text for sharing (WhatsApp, etc.)
  String toText() {
    final sb = StringBuffer();
    for (final line in headerLines) {
      sb.writeln(line);
    }
    // Fixed-width columns for 80mm thermal printer (48 chars total)
    // S.No=4, Particulars=22, Qty=5, Rate=9, Amt=8
    sb.writeln('S.No Particulars           Qty    Rate      Amt');
    sb.writeln('\u2500' * 48);
    for (final row in rows) {
      final sno = row.sNo.toString().padLeft(2);
      final name = row.productName.length > 22
          ? row.productName.substring(0, 22)
          : row.productName.padRight(22);
      final qty = row.qty.toString().padLeft(4);
      final rate = _fmt(row.rate).padLeft(9);
      final amt = _fmt(row.amount).padLeft(8);
      sb.writeln('$sno  $name $qty $rate $amt');
    }
    for (final line in totalLines) {
      sb.writeln(line);
    }
    for (final line in footerLines) {
      sb.writeln(line);
    }
    return sb.toString();
  }

  String _fmt(double v) => v.toStringAsFixed(2);
}

class ThermalInvoice {
  static ThermalReceiptData generate({
    required Sale sale,
    required String shopName,
    String? shopTagline,
    String? shopAddress,
    String? customerName,
    String? gstin,
    String? cashierName,
    bool useTamil = false,
    Map<String, String>? tamilNames,
    String? shopNameTamil,
  }) {
    final now = AppTimezone.toIst(sale.createdAt);
    final dateStr = DateFormat('dd/MM/yyyy').format(now);
    final timeStr = DateFormat('hh:mm a').format(now);
    final saleId = sale.id.length > 8
        ? sale.id.substring(0, 8)
        : sale.id.toUpperCase();

    final displayName =
        (useTamil && shopNameTamil != null && shopNameTamil.isNotEmpty)
        ? shopNameTamil
        : shopName;

    final header = <String>[
      displayName,
      'QUOTATION',
      'Date: $dateStr  Time: $timeStr',
      if (customerName != null && customerName.isNotEmpty)
        'Customer: $customerName',
    ];

    final rows = <ThermalRow>[];
    int totalQty = 0;
    double totalAmount = 0;
    int sno = 0;

    for (final item in sale.items) {
      sno++;
      final name =
          (useTamil &&
              tamilNames != null &&
              tamilNames.containsKey(item.productId))
          ? tamilNames[item.productId]!
          : item.name;
      final tierBadge = item.tier == 'wholesale' ? ' [W]' : item.tier == 'bulk' ? ' [B]' : '';
      final rateBadge = item.rateLabel != null && item.rateLabel!.isNotEmpty ? ' (${item.rateLabel})' : '';
      final qty = item.qty;
      final rate = item.price;
      final total = item.total;
      totalQty += qty;
      totalAmount += total;

      rows.add(
        ThermalRow(
          sNo: sno,
          productName: '$name$tierBadge$rateBadge',
          qty: qty,
          rate: rate,
          amount: total,
        ),
      );
    }

    final totals = <String>[];
    totals.add('Total Items: $sno');
    if (sale.discount > 0) totals.add('Discount: -${_price(sale.discount)}');
    if (sale.extraCharges > 0)
      totals.add('Extra: +${_price(sale.extraCharges)}');
    if (sale.roundOff != 0) {
      totals.add(
        'Round Off: ${sale.roundOff > 0 ? '+' : ''}${sale.roundOff.toStringAsFixed(2)}',
      );
    }
    totals.add('NET TOTAL: ${_price(sale.finalAmount)}');

    return ThermalReceiptData(
      headerLines: header,
      rows: rows,
      totalLines: totals,
      footerLines: const ['Thank you for shopping with us!'],
    );
  }

  static ThermalReceiptData generateFromItems({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double discount,
    required double finalAmount,
    required String paymentMethod,
    required bool isCredit,
    required DateTime createdAt,
    required String saleId,
    required String shopName,
    String? shopTagline,
    String? shopAddress,
    String? gstin,
    String? cashierName,
    bool useTamil = false,
    Map<String, String>? tamilNames,
    String? shopNameTamil,
  }) {
    final istCreated = AppTimezone.toIst(createdAt);
    final dateStr = DateFormat('dd/MM/yyyy').format(istCreated);
    final timeStr = DateFormat('hh:mm a').format(istCreated);
    final shortId = saleId.length > 8
        ? saleId.substring(0, 8)
        : saleId.toUpperCase();

    final displayName =
        (useTamil && shopNameTamil != null && shopNameTamil.isNotEmpty)
        ? shopNameTamil
        : shopName;

    final header = <String>[
      displayName,
      'QUOTATION',
      'Date: $dateStr  Time: $timeStr',
    ];

    final rows = <ThermalRow>[];
    int totalQty = 0;
    int sno = 0;

    for (final item in items) {
      sno++;
      final productId = item['id'] as String? ?? '';
      final name =
          (useTamil && tamilNames != null && tamilNames.containsKey(productId))
          ? tamilNames[productId]!
          : (item['name'] as String? ?? '');
      final qty = item['qty'] ?? 0;
      final rate = ((item['price'] as num?) ?? 0).toDouble();
      final total = ((item['total'] as num?) ?? 0).toDouble();
      totalQty += qty as int;

      rows.add(
        ThermalRow(
          sNo: sno,
          productName: name,
          qty: qty,
          rate: rate,
          amount: total,
        ),
      );
    }

    final totals = <String>[];
    totals.add('Total Items: $sno');
    if (discount > 0) totals.add('Discount: -${_price(discount)}');
    totals.add('NET TOTAL: ${_price(finalAmount)}');

    return ThermalReceiptData(
      headerLines: header,
      rows: rows,
      totalLines: totals,
      footerLines: const ['Thank you for shopping with us!'],
    );
  }

  static String _price(double amount) => amount.toStringAsFixed(2);

  static String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return 'CASH';
      case 'upi':
      case 'digital':
        return 'UPI';
      case 'credit':
        return 'CREDIT';
      case 'split':
        return 'SPLIT';
      default:
        return method.toUpperCase();
    }
  }
}
