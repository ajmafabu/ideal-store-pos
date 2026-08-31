import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/customer.dart';
import '../models/supplier.dart';
import '../utils/app_timezone.dart';

class StatementPdfGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 2);
  static final _dateFormat = DateFormat('dd MMM yyyy');
  static final _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');

  static pw.Font? _notoSansFont;
  static pw.Font? _notoSansBoldFont;

  static Future<pw.Font> _getNotoSans() async {
    _notoSansFont ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    return _notoSansFont!;
  }

  static Future<pw.Font> _getNotoSansBold() async {
    _notoSansBoldFont ??= await _getNotoSans();
    return _notoSansBoldFont!;
  }

  static pw.TextStyle _regular(pw.Font f, {double? size, PdfColor? color}) =>
      pw.TextStyle(font: f, fontSize: size, color: color);

  static pw.TextStyle _bold(pw.Font fb, {double? size, PdfColor? color}) =>
      pw.TextStyle(font: fb, fontSize: size, color: color);

  static Future<void> generateCustomerStatement({
    required Customer customer,
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> payments,
  }) async {
    final pdf = pw.Document();
    final f = await _getNotoSans();
    final fb = await _getNotoSansBold();

    final allTransactions = _buildCustomerTimeline(sales, payments);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildCustomerHeader(customer, f, fb),
        build: (context) => [
          pw.SizedBox(height: 10),
          _buildSummaryRow(customer.totalCredit, f, fb),
          pw.SizedBox(height: 20),
          pw.Text('Transaction History', style: _bold(fb, size: 14)),
          pw.SizedBox(height: 10),
          if (allTransactions.isEmpty)
            pw.Text('No transactions found', style: _regular(f))
          else
            _buildTransactionTable(allTransactions, f, fb),
        ],
        footer: (context) => _buildFooter(f),
      ),
    );

    await _saveAndShare(pdf, '${customer.name}_statement.pdf');
  }

  static Future<void> generateSupplierStatement({
    required Supplier supplier,
    required List<Map<String, dynamic>> purchases,
    required List<Map<String, dynamic>> payments,
  }) async {
    final pdf = pw.Document();
    final f = await _getNotoSans();
    final fb = await _getNotoSansBold();

    final allTransactions = _buildSupplierTimeline(purchases, payments);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildSupplierHeader(supplier, f, fb),
        build: (context) => [
          pw.SizedBox(height: 10),
          _buildSupplierSummaryRow(supplier.totalDues, f, fb),
          pw.SizedBox(height: 20),
          pw.Text('Transaction History', style: _bold(fb, size: 14)),
          pw.SizedBox(height: 10),
          if (allTransactions.isEmpty)
            pw.Text('No transactions found', style: _regular(f))
          else
            _buildTransactionTable(allTransactions, f, fb),
        ],
        footer: (context) => _buildFooter(f),
      ),
    );

    await _saveAndShare(pdf, '${supplier.name}_statement.pdf');
  }

  static Future<void> generateCustomerBalanceList({
    required List<Customer> customers,
  }) async {
    final pdf = pw.Document();
    final f = await _getNotoSans();
    final fb = await _getNotoSansBold();

    final debtors = customers.where((c) => c.totalCredit > 0).toList();
    final totalDebt = debtors.fold(0.0, (sum, c) => sum + c.totalCredit);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildBalanceListHeader('Customer Balance Report', customers.length, totalDebt, f, fb),
        build: (context) => [
          pw.SizedBox(height: 20),
          _buildBalanceTable(debtors, 'customer', f, fb),
        ],
        footer: (context) => _buildFooter(f),
      ),
    );

    await _saveAndShare(pdf, 'customer_balances.pdf');
  }

  static Future<void> generateSupplierBalanceList({
    required List<Supplier> suppliers,
  }) async {
    final pdf = pw.Document();
    final f = await _getNotoSans();
    final fb = await _getNotoSansBold();

    final debtors = suppliers.where((s) => s.totalDues > 0).toList();
    final totalDues = debtors.fold(0.0, (sum, s) => sum + s.totalDues);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildBalanceListHeader('Supplier Balance Report', suppliers.length, totalDues, f, fb),
        build: (context) => [
          pw.SizedBox(height: 20),
          _buildBalanceTable(debtors, 'supplier', f, fb),
        ],
        footer: (context) => _buildFooter(f),
      ),
    );

    await _saveAndShare(pdf, 'supplier_balances.pdf');
  }

  static pw.Widget _buildCustomerHeader(Customer customer, pw.Font f, pw.Font fb) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('IDEAL STORE', style: _bold(fb, size: 20)),
        pw.Text('Customer Statement', style: _regular(f, size: 12, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text(customer.name, style: _bold(fb, size: 16)),
        if (customer.phone != null) pw.Text('Phone: ${customer.phone}', style: _regular(f)),
        if (customer.address != null && customer.address!.isNotEmpty)
          pw.Text('Address: ${customer.address}', style: _regular(f)),
        pw.Text('As of: ${_dateFormat.format(AppTimezone.nowIst())}', style: _regular(f, size: 10, color: PdfColors.grey600)),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _buildSupplierHeader(Supplier supplier, pw.Font f, pw.Font fb) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('IDEAL STORE', style: _bold(fb, size: 20)),
        pw.Text('Supplier Statement', style: _regular(f, size: 12, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text(supplier.name, style: _bold(fb, size: 16)),
        if (supplier.phone != null) pw.Text('Phone: ${supplier.phone}', style: _regular(f)),
        if (supplier.gstNumber != null) pw.Text('GST: ${supplier.gstNumber}', style: _regular(f)),
        pw.Text('As of: ${_dateFormat.format(AppTimezone.nowIst())}', style: _regular(f, size: 10, color: PdfColors.grey600)),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _buildSummaryRow(double totalCredit, pw.Font f, pw.Font fb) {
    final bgColor = totalCredit > 0 ? const PdfColor(1.0, 0.95, 0.88) : const PdfColor(0.91, 0.96, 0.91);
    final textColor = totalCredit > 0 ? const PdfColor(0.9, 0.32, 0.0) : const PdfColor(0.18, 0.49, 0.2);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Column(
            children: [
              pw.Text('Total Outstanding', style: _regular(f, size: 10)),
              pw.SizedBox(height: 4),
              pw.Text(
                _currencyFormat.format(totalCredit),
                style: _bold(fb, size: 18, color: textColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSupplierSummaryRow(double totalDues, pw.Font f, pw.Font fb) {
    final bgColor = totalDues > 0 ? const PdfColor(1.0, 0.95, 0.88) : const PdfColor(0.91, 0.96, 0.91);
    final textColor = totalDues > 0 ? const PdfColor(0.9, 0.32, 0.0) : const PdfColor(0.18, 0.49, 0.2);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Column(
            children: [
              pw.Text('Total Due to Supplier', style: _regular(f, size: 10)),
              pw.SizedBox(height: 4),
              pw.Text(
                _currencyFormat.format(totalDues),
                style: _bold(fb, size: 18, color: textColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildBalanceListHeader(String title, int count, double totalAmount, pw.Font f, pw.Font fb) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('IDEAL STORE', style: _bold(fb, size: 20)),
        pw.Text(title, style: _regular(f, size: 12, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated: ${_dateTimeFormat.format(AppTimezone.nowIst())}', style: _regular(f, size: 10, color: PdfColors.grey600)),
            pw.Text('$count entries | Total: ${_currencyFormat.format(totalAmount)}', style: _bold(fb, size: 10)),
          ],
        ),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _buildTransactionTable(List<_TransactionEntry> entries, pw.Font f, pw.Font fb) {
    return pw.Table.fromTextArray(
      headerStyle: _bold(fb, size: 9),
      headerAlignment: pw.Alignment.centerLeft,
      cellStyle: _regular(f, size: 9),
      cellAlignment: pw.Alignment.centerLeft,
      headers: ['Date', 'Type', 'Description', 'Debit', 'Credit', 'Balance'],
      data: entries.map((e) => [
        _dateFormat.format(e.date),
        e.type,
        e.description,
        e.debit > 0 ? _currencyFormat.format(e.debit) : '-',
        e.credit > 0 ? _currencyFormat.format(e.credit) : '-',
        _currencyFormat.format(e.runningBalance),
      ]).toList(),
      columnWidths: {
        0: const pw.FixedColumnWidth(80),
        1: const pw.FixedColumnWidth(60),
        2: const pw.FlexColumnWidth(3),
        3: const pw.FixedColumnWidth(75),
        4: const pw.FixedColumnWidth(75),
        5: const pw.FixedColumnWidth(80),
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColor(0.96, 0.96, 0.96)),
      headerPadding: const pw.EdgeInsets.all(6),
      cellPadding: const pw.EdgeInsets.all(6),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColor(0.98, 0.98, 0.98)),
    );
  }

  static pw.Widget _buildBalanceTable(List<dynamic> entries, String type, pw.Font f, pw.Font fb) {
    if (entries.isEmpty) {
      return pw.Text('No outstanding balances', style: _regular(f));
    }
    return pw.Table.fromTextArray(
      headerStyle: _bold(fb, size: 9),
      cellStyle: _regular(f, size: 9),
      headers: ['#', 'Name', 'Phone', 'Balance'],
      data: entries.asMap().entries.map((entry) {
        final i = entry.key + 1;
        final item = entry.value;
        final name = item.name;
        final phone = item.phone ?? '-';
        final balance = type == 'customer' ? item.totalCredit : item.totalDues;
        return ['$i', name, phone, _currencyFormat.format(balance)];
      }).toList(),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FixedColumnWidth(90),
      },
      headerDecoration: const pw.BoxDecoration(color: PdfColor(0.96, 0.96, 0.96)),
      headerPadding: const pw.EdgeInsets.all(6),
      cellPadding: const pw.EdgeInsets.all(6),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColor(0.98, 0.98, 0.98)),
    );
  }

  static pw.Widget _buildFooter(pw.Font f) {
    return pw.Column(
      children: [
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated by Ideal Store POS | ${_dateTimeFormat.format(AppTimezone.nowIst())}',
          style: _regular(f, size: 8, color: PdfColors.grey500),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  static List<_TransactionEntry> _buildCustomerTimeline(
    List<Map<String, dynamic>> sales,
    List<Map<String, dynamic>> payments,
  ) {
    final entries = <_TransactionEntry>[];

    for (final sale in sales) {
      final date = DateTime.tryParse(sale['created_at'] ?? '') ?? DateTime.now();
      final amount = (sale['final_amount'] as num?)?.toDouble() ?? 0;
      final saleId = sale['invoice_number'] ?? (() { final s = sale['id']?.toString() ?? ''; return s.length >= 8 ? s.substring(0, 8) : s; })() ?? '';
      entries.add(_TransactionEntry(
        date: date,
        type: 'Sale',
        description: 'Invoice #$saleId',
        debit: amount,
        credit: 0,
      ));
    }

    for (final payment in payments) {
      final date = DateTime.tryParse(payment['created_at'] ?? '') ?? DateTime.now();
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
      final method = payment['payment_method'] ?? 'cash';
      entries.add(_TransactionEntry(
        date: date,
        type: 'Payment',
        description: 'Payment via $method',
        debit: 0,
        credit: amount,
      ));
    }

    entries.sort((a, b) => a.date.compareTo(b.date));

    double runningBalance = 0;
    for (final entry in entries) {
      runningBalance += entry.debit - entry.credit;
      entry.runningBalance = runningBalance;
    }

    return entries;
  }

  static List<_TransactionEntry> _buildSupplierTimeline(
    List<Map<String, dynamic>> purchases,
    List<Map<String, dynamic>> payments,
  ) {
    final entries = <_TransactionEntry>[];

    for (final purchase in purchases) {
      final date = DateTime.tryParse(purchase['created_at'] ?? '') ?? DateTime.now();
      final amount = (purchase['total_amount'] as num?)?.toDouble() ?? 0;
      final refNo = purchase['reference_number'] ?? (() { final s = purchase['id']?.toString() ?? ''; return s.length >= 8 ? s.substring(0, 8) : s; })() ?? '';
      entries.add(_TransactionEntry(
        date: date,
        type: 'Purchase',
        description: 'Ref #$refNo',
        debit: amount,
        credit: 0,
      ));
    }

    for (final payment in payments) {
      final date = DateTime.tryParse(payment['created_at'] ?? '') ?? DateTime.now();
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
      final method = payment['payment_method'] ?? 'cash';
      entries.add(_TransactionEntry(
        date: date,
        type: 'Payment',
        description: 'Payment via $method',
        debit: 0,
        credit: amount,
      ));
    }

    entries.sort((a, b) => a.date.compareTo(b.date));

    double runningBalance = 0;
    for (final entry in entries) {
      runningBalance += entry.debit - entry.credit;
      entry.runningBalance = runningBalance;
    }

    return entries;
  }

  static Future<void> _saveAndShare(pw.Document pdf, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: fileName);
  }
}

class _TransactionEntry {
  final DateTime date;
  final String type;
  final String description;
  final double debit;
  final double credit;
  double runningBalance;

  _TransactionEntry({
    required this.date,
    required this.type,
    required this.description,
    required this.debit,
    required this.credit,
    this.runningBalance = 0,
  });
}
