import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../utils/app_timezone.dart';

class InvoiceGenerator {
  static const int lineWidth = 32;
  static const int colItem = 18;
  static const int colQty = 5;
  static const int colPrice = 8;
  static const int colLabel = 24;
  static const int colValue = 8;

  // Cached fonts
  static pw.Font? _notoSansFont;
  static pw.Font? _notoSansBoldFont;
  static pw.Font? _tamilFont;

  static Future<pw.Font> getNotoSans() async {
    _notoSansFont ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    return _notoSansFont!;
  }

  static Future<pw.Font> getNotoSansBold() async {
    _notoSansBoldFont ??= await getNotoSans();
    return _notoSansBoldFont!;
  }

  static Future<pw.Font> getTamilFont() async {
    _tamilFont ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansTamil-Regular.ttf'));
    return _tamilFont!;
  }

  static String _saleId(Sale sale) {
    if (sale.id.isNotEmpty) return sale.id.length >= 8 ? sale.id.substring(0, 8).toUpperCase() : sale.id.toUpperCase();
    return sale.createdAt.millisecondsSinceEpoch.toRadixString(16).substring(0, 8).toUpperCase();
  }

  static pw.Widget buildInvoice(
    Sale sale, {
    String? shopName,
    String? shopAddress,
    String? shopNameTamil,
    bool useTamil = false,
    Map<String, String>? tamilNames,
    pw.Font? tamilFont,
    pw.Font? font,
    pw.Font? fontBold,
  }) {
    final f = font ?? pw.Font.times();
    final fb = fontBold ?? pw.Font.timesBold();
    final tFont = tamilFont ?? f;
    final totalItemDiscount = sale.items.fold(0.0, (sum, item) => sum + item.discountAmount);
    final totalGst = sale.items.fold(0.0, (sum, item) => sum + item.gstAmount);

    List<pw.Widget> lines = [];

    // ── Header ──
    final displayShopName = (useTamil && shopNameTamil != null && shopNameTamil.isNotEmpty)
        ? shopNameTamil
        : shopName ?? 'IDEAL STORE';
    final shopNameFont = (useTamil && shopNameTamil != null && shopNameTamil.isNotEmpty)
        ? tFont
        : fb;
    lines.add(pw.Center(child: pw.Text(displayShopName, style: pw.TextStyle(font: shopNameFont, fontSize: 10))));
    if (shopAddress != null && shopAddress.isNotEmpty) {
      lines.add(pw.Center(child: pw.Text(shopAddress, style: pw.TextStyle(font: f, fontSize: 7))));
    }
    lines.add(pw.Center(child: pw.Text('Smart Store - Smart Business', style: pw.TextStyle(font: f, fontSize: 7))));
    lines.add(pw.Center(child: pw.Text(_sep(), style: pw.TextStyle(font: f, fontSize: 7))));

    // ── Invoice info ──
    lines.add(pw.Text(_leftRight('Invoice: #${_saleId(sale)}', ''), style: pw.TextStyle(font: f, fontSize: 8)));
    lines.add(pw.Text(_leftRight('Date: ${DateFormat('dd MMM yyyy hh:mm a').format(AppTimezone.toIst(sale.createdAt))}', ''), style: pw.TextStyle(font: f, fontSize: 8)));
    lines.add(pw.Center(child: pw.Text(_sep(), style: pw.TextStyle(font: f, fontSize: 7))));

    // ── Item header ──
    lines.add(pw.Text(_itemRow('ITEM', 'QTY', 'PRICE'), style: pw.TextStyle(font: fb, fontSize: 8)));
    lines.add(pw.Center(child: pw.Text(_sep(), style: pw.TextStyle(font: f, fontSize: 7))));

    // ── Items ──
    final nameStyle = useTamil
        ? pw.TextStyle(font: tFont, fontSize: 8)
        : pw.TextStyle(font: f, fontSize: 8);

    for (final item in sale.items) {
      final name = (useTamil && tamilNames != null && tamilNames.containsKey(item.productId))
          ? tamilNames[item.productId]!
          : item.name;
      final tierBadge = item.tier == 'wholesale' ? ' [W]' : item.tier == 'bulk' ? ' [B]' : '';
      final rateBadge = item.rateLabel != null && item.rateLabel!.isNotEmpty ? ' (${item.rateLabel})' : '';
      final qty = item.qty;
      final total = item.total;
      final hasDiscount = item.discount > 0;

      // Wrap long names
      final nameLines = _wrapText('$name$tierBadge$rateBadge', colItem);
      if (nameLines.length > 1) {
        lines.add(pw.Text(_itemRow(nameLines[0], '$qty', _price(total)), style: nameStyle));
        for (int i = 1; i < nameLines.length; i++) {
          lines.add(pw.Text(_itemRow(nameLines[i], '', ''), style: nameStyle));
        }
      } else {
        lines.add(pw.Text(_itemRow(name, '$qty', _price(total)), style: nameStyle));
      }

      if (hasDiscount) {
        final discText = '${item.discount.toStringAsFixed(0)}% OFF';
        lines.add(pw.Text(_itemRow('  $discText', '', '-${_price(item.discountAmount)}'), style: pw.TextStyle(font: f, fontSize: 7)));
      }

      if (item.gstRate > 0) {
        lines.add(pw.Text(_itemRow('  GST ${item.gstRate.toStringAsFixed(0)}%', '', _price(item.gstAmount)), style: pw.TextStyle(font: f, fontSize: 7)));
      }
    }

    lines.add(pw.Center(child: pw.Text(_sep(), style: pw.TextStyle(font: f, fontSize: 7))));

    // ── Totals ──
    lines.add(pw.Text(_totalRow('Subtotal:', _price(sale.totalAmount)), style: pw.TextStyle(font: f, fontSize: 8)));

    if (totalItemDiscount > 0) {
      lines.add(pw.Text(_totalRow('Item Discount:', '-${_price(totalItemDiscount)}'), style: pw.TextStyle(font: f, fontSize: 8)));
    }

    if (sale.discount > 0) {
      lines.add(pw.Text(_totalRow('Bill Discount:', '-${_price(sale.discount)}'), style: pw.TextStyle(font: f, fontSize: 8)));
    }

    if (totalGst > 0) {
      lines.add(pw.Text(_totalRow('Tax:', _price(totalGst)), style: pw.TextStyle(font: f, fontSize: 8)));
    }

    if (sale.roundOff != 0) {
      lines.add(pw.Text(_totalRow('Round Off:', '${sale.roundOff > 0 ? '+' : ''}${sale.roundOff.toStringAsFixed(2)}'), style: pw.TextStyle(font: f, fontSize: 8)));
    }

    lines.add(pw.Center(child: pw.Text(_sep(), style: pw.TextStyle(font: f, fontSize: 7))));

    // ── Grand total ──
    lines.add(pw.Text(_totalRow('TOTAL', _price(sale.finalAmount)), style: pw.TextStyle(font: fb, fontSize: 10)));

    lines.add(pw.Center(child: pw.Text(_sep(), style: pw.TextStyle(font: f, fontSize: 7))));

    // ── Payment ──
    lines.add(pw.Text(_leftRight('Payment: ${_paymentLabel(sale.paymentMethod)}', ''), style: pw.TextStyle(font: f, fontSize: 8)));
    if (sale.isCredit) {
      lines.add(pw.Text(_leftRight('Status: CREDIT', ''), style: pw.TextStyle(font: f, fontSize: 8)));
      lines.add(pw.Text(_leftRight('Paid:', _price(sale.amountPaid)), style: pw.TextStyle(font: f, fontSize: 8)));
      lines.add(pw.Text(_leftRight('Due:', _price(sale.dueAmount)), style: pw.TextStyle(font: fb, fontSize: 9)));
    }
    if (sale.paymentMethod == 'split') {
      lines.add(pw.Text(_leftRight('Cash:', _price(sale.cashAmount)), style: pw.TextStyle(font: f, fontSize: 8)));
      lines.add(pw.Text(_leftRight('UPI:', _price(sale.digitalAmount)), style: pw.TextStyle(font: f, fontSize: 8)));
    }

    lines.add(pw.Center(child: pw.Text(_sep(), style: pw.TextStyle(font: f, fontSize: 7))));

    // ── Footer ──
    lines.add(pw.Center(child: pw.Text('Thank you!', style: pw.TextStyle(font: f, fontSize: 8))));
    lines.add(pw.Center(child: pw.Text('Visit Again', style: pw.TextStyle(font: f, fontSize: 8))));

    // E-Invoice note
    lines.add(pw.SizedBox(height: 4));
    lines.add(pw.Center(child: pw.Text('E-Invoice: Not applicable for B2C', style: pw.TextStyle(font: f, fontSize: 6, color: PdfColors.grey600))));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: lines,
    );
  }

  // ── Helpers ──

  static String _price(double amount) => amount.toStringAsFixed(2);

  static String _sep() => '─' * lineWidth;

  static String _itemRow(String item, String qty, String price) {
    return '${_padRight(item, colItem)}${_padLeft(qty, colQty)}${_padLeft(price, colPrice)}';
  }

  static String _totalRow(String label, String value) {
    return '${_padRight(label, colLabel)}${_padLeft(value, colValue)}';
  }

  static String _leftRight(String left, String right) {
    if (right.isEmpty) return left;
    return '${_padRight(left, colLabel)}${_padLeft(right, colValue)}';
  }

  static String _paymentLabel(String method) {
    switch (method) {
      case 'cash': return 'CASH';
      case 'upi':
      case 'digital': return 'UPI';
      case 'credit': return 'CREDIT';
      case 'split': return 'SPLIT';
      default: return method.toUpperCase();
    }
  }

  static List<String> _wrapText(String text, int maxWidth) {
    if (text.isEmpty) return [''];
    if (text.length <= maxWidth) return [text];

    final lines = <String>[];
    final words = text.split(' ');
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if (('$current $word').length <= maxWidth) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  static String _padRight(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    return text + ' ' * (width - text.length);
  }

  static String _padLeft(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    return ' ' * (width - text.length) + text;
  }

  // ── Generate & Share PDF ──

  static Future<void> generateAndPrint(
    Sale sale, {
    String? shopName,
    String? shopAddress,
    String? shopNameTamil,
    bool useTamil = false,
    Map<String, String>? tamilNames,
  }) async {
    final font = await getNotoSans();
    final fontBold = await getNotoSansBold();
    pw.Font? tFont;
    if (useTamil) {
      tFont = await getTamilFont();
    }
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      build: (context) => [
        buildInvoice(
          sale,
          shopName: shopName,
          shopAddress: shopAddress,
          shopNameTamil: shopNameTamil,
          useTamil: useTamil,
          tamilNames: tamilNames,
          tamilFont: tFont,
          font: font,
          fontBold: fontBold,
        )
      ],
    ));
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Invoice_${_saleId(sale)}',
    );
  }

  static Future<void> shareInvoice(
    Sale sale, {
    String? shopName,
    String? shopAddress,
    String? shopNameTamil,
    bool useTamil = false,
    Map<String, String>? tamilNames,
  }) async {
    final font = await getNotoSans();
    final fontBold = await getNotoSansBold();
    pw.Font? tFont;
    if (useTamil) {
      tFont = await getTamilFont();
    }
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      build: (context) => [
        buildInvoice(
          sale,
          shopName: shopName,
          shopAddress: shopAddress,
          shopNameTamil: shopNameTamil,
          useTamil: useTamil,
          tamilNames: tamilNames,
          tamilFont: tFont,
          font: font,
          fontBold: fontBold,
        )
      ],
    ));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'invoice_${_saleId(sale)}.pdf');
  }
}
