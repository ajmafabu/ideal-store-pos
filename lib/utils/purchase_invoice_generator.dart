import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/purchase.dart';
import '../utils/app_timezone.dart';

class PurchaseInvoiceGenerator {
  static String _purchaseId(Purchase purchase) {
    if (purchase.id.isNotEmpty) return purchase.id.length >= 8 ? purchase.id.substring(0, 8).toUpperCase() : purchase.id.toUpperCase();
    return purchase.createdAt.millisecondsSinceEpoch.toRadixString(16).substring(0, 8).toUpperCase();
  }

  static pw.Widget _buildInvoice(Purchase purchase) {
    final totalGst = purchase.items.fold(0.0, (sum, item) => sum + item.gstAmount);
    final totalExclGst = purchase.totalAmount - totalGst;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text('IDEAL STORE POS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Purchase Invoice', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.Divider(),
            ],
          ),
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Tax Invoice', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(DateFormat('dd MMM yyyy').format(AppTimezone.toIst(purchase.createdAt))),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(DateFormat('hh:mm a').format(AppTimezone.toIst(purchase.createdAt))),
            pw.Text('#${_purchaseId(purchase)}'),
          ],
        ),
        if (purchase.supplierName != null && purchase.supplierName!.isNotEmpty)
          pw.Row(
            children: [
              pw.Text('Supplier: ', style: pw.TextStyle(fontSize: 9)),
              pw.Text(purchase.supplierName!, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        pw.Divider(),
        pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        pw.Divider(),
        ...purchase.items.map((item) => pw.Column(children: [
          pw.Row(
            children: [
              pw.Expanded(flex: 4, child: pw.Text(item.name, style: pw.TextStyle(fontSize: 9))),
              pw.Expanded(flex: 2, child: pw.Text('${item.qty}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9))),
              pw.Expanded(flex: 3, child: pw.Text('Rs${item.price.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9))),
              pw.Expanded(flex: 3, child: pw.Text('Rs${item.total.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9))),
            ],
          ),
          if (item.gstRate > 0)
            pw.Row(
              children: [
                pw.Expanded(flex: 4, child: pw.Text('  HSN: ${item.hsnCode ?? '-'} | GST: ${item.gstRate.toStringAsFixed(0)}%', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600))),
                pw.Expanded(flex: 8, child: pw.Text('CGST: Rs${item.cgst.toStringAsFixed(2)} | SGST: Rs${item.sgst.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600))),
              ],
            ),
        ])),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Subtotal:', style: pw.TextStyle(fontSize: 9)),
            pw.Text('Rs${purchase.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9)),
          ],
        ),
        if (totalGst > 0) ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total CGST:', style: pw.TextStyle(fontSize: 9)),
              pw.Text('Rs${(totalGst / 2).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total SGST:', style: pw.TextStyle(fontSize: 9)),
              pw.Text('Rs${(totalGst / 2).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total GST:', style: pw.TextStyle(fontSize: 9)),
              pw.Text('Rs${totalGst.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9)),
            ],
          ),
        ],
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('TOTAL:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
            pw.Text('Rs${purchase.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          ],
        ),
        if (purchase.isCredit) ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Paid:', style: pw.TextStyle(fontSize: 9)),
              pw.Text('Rs${purchase.amountPaid.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Due:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text('Rs${purchase.dueAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ],
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Divider(),
        pw.Center(
          child: pw.Text('Thank you!', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
      ],
    );
  }

  static Future<void> generateAndPrint(Purchase purchase) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        build: (context) => [_buildInvoice(purchase)],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Purchase_${_purchaseId(purchase)}',
    );
  }

  static Future<void> shareInvoice(Purchase purchase) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        build: (context) => [_buildInvoice(purchase)],
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'purchase_${_purchaseId(purchase)}.pdf');
  }
}
