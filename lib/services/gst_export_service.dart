import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';

/// GSTR-1 CSV files in the column layout of the GST offline tool (#23):
///   b2b  – invoices to GST-registered customers, one row per tax rate
///   b2cl – inter-state invoices to consumers above the B2C-Large limit
///   b2cs – all other consumer sales, summed by place of supply and rate
///   hsn  – HSN-wise summary (Table 12)
///
/// Every figure is derived from what the database stored on the sale:
/// invoice number, place of supply and the CGST/SGST/IGST split (computed
/// after the bill discount). Line values are spread over the bill the same
/// way the database does, so the files add up to the GSTR-3B summary.
class GstExportService {
  static final GstExportService _instance = GstExportService._internal();
  factory GstExportService() => _instance;
  GstExportService._internal();

  /// B2C-Large threshold for inter-state invoices (₹1 lakh from 1 Aug 2024).
  static const double b2clLimit = 100000;

  static const Map<String, String> stateNames = {
    '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh',
    '05': 'Uttarakhand', '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh',
    '10': 'Bihar', '11': 'Sikkim', '12': 'Arunachal Pradesh', '13': 'Nagaland', '14': 'Manipur',
    '15': 'Mizoram', '16': 'Tripura', '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal',
    '20': 'Jharkhand', '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat',
    '26': 'Dadra & Nagar Haveli & Daman & Diu', '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa',
    '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry',
    '35': 'Andaman & Nicobar Islands', '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh',
    '97': 'Other Territory',
  };

  static String placeOfSupply(String? code) {
    final c = (code ?? '').trim().padLeft(2, '0');
    return '$c-${stateNames[c] ?? 'Unknown'}';
  }

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static String _m(double v) => v.toStringAsFixed(2);
  static String _rate(double r) => r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);

  /// Sales of one IST calendar month with the customer's GSTIN, plus shop settings.
  Future<_MonthData> _load(int month, int year) async {
    final supabase = Supabase.instance.client;
    final start = AppTimezone.toUtc(DateTime(year, month, 1));
    final end = AppTimezone.toUtc(DateTime(year, month + 1, 1));

    final shop = await supabase.from('shop_settings').select().eq('id', 1).maybeSingle();
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await supabase
          .from('sales')
          .select('id, invoice_no, created_at, final_amount, items, place_of_supply, tax_exempt, '
              'cgst_amount, sgst_amount, igst_amount, taxable_amount, customers(name, gstin)')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .order('created_at')
          .range(offset, offset + 999);
      rows.addAll((page as List).map((e) => Map<String, dynamic>.from(e as Map)));
      if (page.length < 1000) break;
      offset += 1000;
    }
    return _MonthData(
      sales: rows,
      shopState: (shop?['state_code'] as String?)?.trim().isNotEmpty == true ? shop!['state_code'] as String : '33',
    );
  }

  /// Splits one sale into per-rate taxable values and tax, scaled so the
  /// totals equal the CGST/SGST/IGST the database stored on the sale.
  List<_RateLine> _rateLines(Map<String, dynamic> sale) {
    final items = (sale['items'] as List? ?? const []).whereType<Map>().toList();
    final finalAmount = _d(sale['final_amount']);
    double lineSum = 0;
    for (final it in items) {
      lineSum += _lineTotal(it);
    }
    if (lineSum <= 0) return [];
    final factor = finalAmount / lineSum; // bill discount, extras, round-off
    final byRate = <double, _RateLine>{};
    for (final it in items) {
      final rate = _d(it['gst_rate']);
      final value = _lineTotal(it) * factor;
      final tax = sale['tax_exempt'] == true ? 0.0 : value * rate / (100 + rate);
      final l = byRate.putIfAbsent(rate, () => _RateLine(rate));
      l.value += value;
      l.tax += tax;
    }
    // align to the stored tax split exactly
    final storedTax = _d(sale['cgst_amount']) + _d(sale['sgst_amount']) + _d(sale['igst_amount']);
    final computedTax = byRate.values.fold<double>(0, (s, l) => s + l.tax);
    final igstShare = storedTax > 0 ? _d(sale['igst_amount']) / storedTax : 0.0;
    for (final l in byRate.values) {
      final tax = computedTax > 0 ? storedTax * l.tax / computedTax : 0.0;
      l.taxable = l.value - tax;
      l.igst = tax * igstShare;
      l.cgst = (tax - l.igst) / 2;
      l.sgst = tax - l.igst - l.cgst;
    }
    return byRate.values.toList();
  }

  static double _lineTotal(Map it) {
    if (it['total'] != null) return _d(it['total']);
    return _d(it['price']) * _d(it['qty']) - _d(it['discount_amount']);
  }

  static String _invoiceNo(Map<String, dynamic> s) =>
      s['invoice_no']?.toString() ?? s['id'].toString().substring(0, 8).toUpperCase();

  static String _invoiceDate(Map<String, dynamic> s) {
    final t = DateTime.tryParse(s['created_at']?.toString() ?? '');
    return t == null ? '' : DateFormat('dd-MMM-yyyy').format(AppTimezone.toIst(t));
  }

  static String _gstinOf(Map<String, dynamic> s) =>
      ((s['customers'] as Map?)?['gstin'] as String?)?.trim().toUpperCase() ?? '';

  Future<File> _write(String name, List<List<dynamic>> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(const ListToCsvConverter().convert(rows));
    Logger.info('GSTR-1 file written: ${file.path}');
    return file;
  }

  String _suffix(int month, int year) => '${year}_${month.toString().padLeft(2, '0')}';

  /// GSTR-1 B2B: one row per invoice and tax rate.
  Future<File?> exportGstr1B2B({required int month, required int year}) async {
    try {
      final data = await _load(month, year);
      final rows = <List<dynamic>>[
        ['GSTIN/UIN of Recipient', 'Receiver Name', 'Invoice Number', 'Invoice date', 'Invoice Value',
         'Place Of Supply', 'Reverse Charge', 'Applicable % of Tax Rate', 'Invoice Type', 'E-Commerce GSTIN',
         'Rate', 'Taxable Value', 'Cess Amount'],
      ];
      for (final s in data.sales) {
        final gstin = _gstinOf(s);
        if (gstin.isEmpty) continue;
        for (final l in _rateLines(s)) {
          rows.add([
            gstin,
            (s['customers'] as Map?)?['name'] ?? '',
            _invoiceNo(s),
            _invoiceDate(s),
            _m(_d(s['final_amount'])),
            placeOfSupply(s['place_of_supply'] as String? ?? data.shopState),
            'N',
            '',
            'Regular B2B',
            '',
            _rate(l.rate),
            _m(l.taxable),
            '0.00',
          ]);
        }
      }
      return _write('gstr1_b2b_${_suffix(month, year)}.csv', rows);
    } catch (e) {
      Logger.error('GSTR-1 B2B export failed', e);
      rethrow;
    }
  }

  /// GSTR-1 consumer sales: B2CS summary (by place of supply and rate) and,
  /// when there are any, B2CL invoices. Returns the B2CS file.
  Future<File?> exportGstr1B2C({required int month, required int year}) async {
    try {
      final data = await _load(month, year);
      final b2cs = <String, _RateLine>{};
      final b2cl = <List<dynamic>>[
        ['Invoice Number', 'Invoice date', 'Invoice Value', 'Place Of Supply', 'Applicable % of Tax Rate',
         'Rate', 'Taxable Value', 'Cess Amount', 'E-Commerce GSTIN'],
      ];
      for (final s in data.sales) {
        if (_gstinOf(s).isNotEmpty) continue;
        final pos = (s['place_of_supply'] as String?) ?? data.shopState;
        final interState = pos.padLeft(2, '0') != data.shopState.padLeft(2, '0');
        final large = interState && _d(s['final_amount']) > b2clLimit;
        for (final l in _rateLines(s)) {
          if (large) {
            b2cl.add([_invoiceNo(s), _invoiceDate(s), _m(_d(s['final_amount'])), placeOfSupply(pos), '',
              _rate(l.rate), _m(l.taxable), '0.00', '']);
          } else {
            final agg = b2cs.putIfAbsent('$pos|${l.rate}', () => _RateLine(l.rate)..pos = pos);
            agg.taxable += l.taxable;
            agg.igst += l.igst;
            agg.cgst += l.cgst;
            agg.sgst += l.sgst;
          }
        }
      }
      final rows = <List<dynamic>>[
        ['Type', 'Place Of Supply', 'Applicable % of Tax Rate', 'Rate', 'Taxable Value', 'Cess Amount', 'E-Commerce GSTIN'],
        for (final l in b2cs.values) ['OE', placeOfSupply(l.pos), '', _rate(l.rate), _m(l.taxable), '0.00', ''],
      ];
      if (b2cl.length > 1) {
        await _write('gstr1_b2cl_${_suffix(month, year)}.csv', b2cl);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final stale = File('${dir.path}/gstr1_b2cl_${_suffix(month, year)}.csv');
        if (await stale.exists()) await stale.delete();
      }
      return _write('gstr1_b2cs_${_suffix(month, year)}.csv', rows);
    } catch (e) {
      Logger.error('GSTR-1 B2C export failed', e);
      rethrow;
    }
  }

  /// HSN-wise summary of outward supplies (Table 12).
  Future<File?> exportHsnSummary({required int month, required int year}) async {
    final data = await _load(month, year);
    final byHsn = <String, Map<String, dynamic>>{};
    for (final s in data.sales) {
      final items = (s['items'] as List? ?? const []).whereType<Map>().toList();
      double lineSum = 0;
      for (final it in items) {
        lineSum += _lineTotal(it);
      }
      if (lineSum <= 0) continue;
      final factor = _d(s['final_amount']) / lineSum;
      final storedTax = _d(s['cgst_amount']) + _d(s['sgst_amount']) + _d(s['igst_amount']);
      final igstShare = storedTax > 0 ? _d(s['igst_amount']) / storedTax : 0.0;
      double computedTax = 0;
      for (final it in items) {
        final r = _d(it['gst_rate']);
        computedTax += _lineTotal(it) * factor * r / (100 + r);
      }
      for (final it in items) {
        final rate = _d(it['gst_rate']);
        final hsn = (it['hsn_code'] as String?)?.trim() ?? '';
        final key = '${hsn.isEmpty ? 'NA' : hsn}|$rate';
        final value = _lineTotal(it) * factor;
        final rawTax = value * rate / (100 + rate);
        final tax = computedTax > 0 && s['tax_exempt'] != true ? storedTax * rawTax / computedTax : 0.0;
        final h = byHsn.putIfAbsent(key, () => {
              'hsn': hsn, 'desc': it['name'] ?? '', 'uqc': (it['unit'] ?? 'NOS').toString().toUpperCase(),
              'rate': rate, 'qty': 0.0, 'value': 0.0, 'taxable': 0.0, 'igst': 0.0, 'cgst': 0.0, 'sgst': 0.0,
            });
        h['qty'] = (h['qty'] as double) + _d(it['qty']);
        h['value'] = (h['value'] as double) + value;
        h['taxable'] = (h['taxable'] as double) + value - tax;
        h['igst'] = (h['igst'] as double) + tax * igstShare;
        h['cgst'] = (h['cgst'] as double) + tax * (1 - igstShare) / 2;
        h['sgst'] = (h['sgst'] as double) + tax * (1 - igstShare) / 2;
      }
    }
    final rows = <List<dynamic>>[
      ['HSN', 'Description', 'UQC', 'Total Quantity', 'Total Value', 'Rate', 'Taxable Value',
       'Integrated Tax Amount', 'Central Tax Amount', 'State/UT Tax Amount', 'Cess Amount'],
      for (final h in byHsn.values)
        [h['hsn'], h['desc'], h['uqc'], (h['qty'] as double).toStringAsFixed(2), _m(h['value'] as double),
         _rate(h['rate'] as double), _m(h['taxable'] as double), _m(h['igst'] as double),
         _m(h['cgst'] as double), _m(h['sgst'] as double), '0.00'],
    ];
    return _write('gstr1_hsn_${_suffix(month, year)}.csv', rows);
  }

  /// Share every GSTR-1 file for the month.
  Future<void> shareGstr1({required int month, required int year}) async {
    final files = <XFile>[];
    final b2b = await exportGstr1B2B(month: month, year: year);
    final b2cs = await exportGstr1B2C(month: month, year: year);
    final hsn = await exportHsnSummary(month: month, year: year);
    for (final f in [b2b, b2cs, hsn]) {
      if (f != null) files.add(XFile(f.path));
    }
    final dir = await getApplicationDocumentsDirectory();
    final b2cl = File('${dir.path}/gstr1_b2cl_${_suffix(month, year)}.csv');
    if (await b2cl.exists()) files.add(XFile(b2cl.path));
    if (files.isNotEmpty) {
      await Share.shareXFiles(files, text: 'GSTR-1 $year-${month.toString().padLeft(2, '0')}');
    }
  }
}

class _MonthData {
  final List<Map<String, dynamic>> sales;
  final String shopState;
  _MonthData({required this.sales, required this.shopState});
}

class _RateLine {
  final double rate;
  String pos = '';
  double value = 0;
  double tax = 0;
  double taxable = 0;
  double igst = 0;
  double cgst = 0;
  double sgst = 0;
  _RateLine(this.rate);
}
