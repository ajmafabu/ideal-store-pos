import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../utils/app_timezone.dart';
import '../utils/tamil_bitmap_renderer.dart';
import 'payment_methods.dart';
import 'qty_format.dart';

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
    // 48 columns (80 mm): # 3 · item 20 · qty 5 · rate 9 · amount 11.
    // The headings line up with the numbers (they did not), and a long name
    // goes on to a second line instead of being cut ("(Box)" was lost).
    sb.writeln('${'#'.padLeft(2)} ${'Item'.padRight(20)}${'Qty'.padLeft(5)}${'Rate'.padLeft(9)}${'Amount'.padLeft(11)}');
    sb.writeln('-' * 48);
    for (final row in rows) {
      final parts = _wrap(row.productName, 20);
      sb.writeln(
        '${row.sNo.toString().padLeft(2)} ${parts.first.padRight(20)}'
        '${formatQty(row.qty).padLeft(5)}${_fmt(row.rate).padLeft(9)}${_fmt(row.amount).padLeft(11)}',
      );
      for (final more in parts.skip(1)) {
        sb.writeln('   $more');
      }
    }
    sb.writeln('-' * 48);
    for (final line in totalLines) {
      // the amount in words can be longer than the paper
      for (final part in _wrap(line, 48)) {
        sb.writeln(part);
      }
    }
    for (final line in footerLines) {
      sb.writeln(line);
    }
    return sb.toString();
  }

  String _fmt(double v) => v.toStringAsFixed(2);

  /// Lines of at most [width] characters, broken between words.
  static List<String> _wrap(String text, int width) {
    final lines = <String>[];
    var line = '';
    for (final word in text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      var w = word;
      while (w.length > width) {
        if (line.isNotEmpty) {
          lines.add(line);
          line = '';
        }
        lines.add(w.substring(0, width));
        w = w.substring(width);
      }
      if (line.isEmpty) {
        line = w;
      } else if (line.length + 1 + w.length <= width) {
        line = '$line $w';
      } else {
        lines.add(line);
        line = w;
      }
    }
    if (line.isNotEmpty || lines.isEmpty) lines.add(line);
    return lines;
  }
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

    final displayName =
        (useTamil && shopNameTamil != null && shopNameTamil.isNotEmpty)
        ? shopNameTamil
        : shopName;

    // the customer: given, or the one saved on the bill (the Windows till
    // printed without it, 18 Oct 2026)
    final customer = (customerName?.trim().isNotEmpty ?? false) ? customerName!.trim() : sale.customerName?.trim();
    final header = <String>[
      // no address on the thermal bill (owner, 18 Oct 2026)
      displayName,
      'QUOTATION',
      // a bill saved offline gets its real number when it syncs
      'Bill No: ${sale.invoiceLabel}${sale.invoiceNo == null ? ' (offline - provisional)' : ''}',
      'Date: $dateStr  Time: $timeStr',
      if (customer != null && customer.isNotEmpty) 'Customer: $customer',
    ];

    final rows = <ThermalRow>[];
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

    final pieces = sale.items.fold<double>(0, (t, i) => t + i.qty);
    final totals = <String>[];
    totals.add('Total Items: $sno   Qty: ${formatQty(pieces)}');
    final adjusted = sale.discount > 0 || sale.extraCharges > 0 || sale.roundOff != 0;
    // the sum of the lines, so the discount can be checked on paper
    if (adjusted) totals.add('Sub Total: ${_price(sale.totalAmount)}');
    if (sale.discount > 0) totals.add('Discount: -${_price(sale.discount)}');
    if (sale.extraCharges > 0) totals.add('Extra: +${_price(sale.extraCharges)}');
    if (sale.roundOff != 0) {
      totals.add('Round Off: ${sale.roundOff > 0 ? '+' : ''}${sale.roundOff.toStringAsFixed(2)}');
    }
    totals.add('NET TOTAL: ${_price(sale.finalAmount)}');
    totals.add(amountInWords(sale.finalAmount));
    // how it was paid; a credit bill shows what is still owed (it showed
    // neither, 18 Oct 2026)
    if (sale.isCredit) {
      if (sale.amountPaid > 0.004) totals.add('Paid: ${_price(sale.amountPaid)}');
      totals.add('Balance Due: ${_price(sale.dueAmount)}');
    } else if (PaymentMethods.normalize(sale.paymentMethod) == PaymentMethods.split) {
      totals.add('Paid: Cash ${_price(sale.cashAmount)} + UPI ${_price(sale.digitalAmount)}');
    } else {
      totals.add('Paid by: ${PaymentMethods.label(sale.paymentMethod)}');
    }

    return ThermalReceiptData(
      headerLines: header,
      rows: rows,
      totalLines: totals,
      footerLines: const ['Thank you! Visit again'],
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
    int sno = 0;

    for (final item in items) {
      sno++;
      final productId = item['id'] as String? ?? '';
      final name =
          (useTamil && tamilNames != null && tamilNames.containsKey(productId))
          ? tamilNames[productId]!
          : (item['name'] as String? ?? '');
      final qty = ((item['qty'] as num?) ?? 0).toDouble();
      final rate = ((item['price'] as num?) ?? 0).toDouble();
      final total = ((item['total'] as num?) ?? 0).toDouble();

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
      footerLines: const ['Thank you! Visit again'],
    );
  }

  static String _price(double amount) => amount.toStringAsFixed(2);

  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen',
    'Eighteen', 'Nineteen',
  ];
  static const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

  static String _under100(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 > 0 ? ' ${_ones[n % 10]}' : ''}';

  static String _under1000(int n) {
    final h = n ~/ 100, r = n % 100;
    return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) _under100(r)].join(' ');
  }

  /// "Rupees Five Hundred Ten Only", the Indian way (lakh, crore), with
  /// paise when there are any.
  static String amountInWords(double amount) {
    final paiseTotal = (amount.abs() * 100).round();
    var rupees = paiseTotal ~/ 100;
    final paise = paiseTotal % 100;
    if (rupees == 0 && paise == 0) return 'Rupees Zero Only';
    final parts = <String>[];
    final crore = rupees ~/ 10000000;
    rupees %= 10000000;
    final lakh = rupees ~/ 100000;
    rupees %= 100000;
    final thousand = rupees ~/ 1000;
    rupees %= 1000;
    if (crore > 0) parts.add('${_under1000(crore)} Crore');
    if (lakh > 0) parts.add('${_under100(lakh)} Lakh');
    if (thousand > 0) parts.add('${_under100(thousand)} Thousand');
    if (rupees > 0) parts.add(_under1000(rupees));
    final words = parts.join(' ');
    final p = paise > 0 ? '${words.isEmpty ? '' : ' and '}${_under100(paise)} Paise' : '';
    return '${words.isEmpty ? '' : 'Rupees $words'}$p Only'.trim();
  }

}
