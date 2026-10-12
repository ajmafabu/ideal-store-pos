import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../models/product.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';

/// Columns of the GST sheet. The accountant fills HSN code and GST %;
/// the product id stays so the sheet can be imported back later.
const productGstSheetHeader = [
  'Product ID (do not change)',
  'Name',
  'Tamil name',
  'Category',
  'Barcode',
  'Unit',
  'Selling price',
  'HSN code',
  'GST %',
];

/// Rows for the GST sheet, sorted by category then name so items with the
/// same HSN code sit together. No cost price or stock: safe to hand over.
List<List<dynamic>> productGstSheetRows(List<Product> products) {
  final sorted = [...products]
    ..sort((a, b) {
      final c = (a.category ?? '').toLowerCase().compareTo((b.category ?? '').toLowerCase());
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return [
    productGstSheetHeader,
    for (final p in sorted)
      [
        p.id,
        p.name,
        p.tamilName ?? '',
        p.category ?? '',
        p.barcode ?? '',
        p.unit,
        p.sellingPrice,
        p.hsnCode ?? '',
        p.gstRate == p.gstRate.roundToDouble() ? p.gstRate.toInt() : p.gstRate,
      ],
  ];
}

/// Writes the sheet as a CSV that Excel opens directly (UTF-8 BOM keeps
/// Tamil names readable). Returns the file.
Future<File> exportProductGstSheet(List<Product> products) async {
  final dir = await getApplicationDocumentsDirectory();
  final stamp = AppTimezone.nowIst().toIso8601String().substring(0, 10);
  final file = File('${dir.path}${Platform.pathSeparator}products_gst_$stamp.csv');
  final csv = const ListToCsvConverter().convert(productGstSheetRows(products));
  await file.writeAsString('﻿$csv');
  Logger.info('Product GST sheet written: ${file.path}');
  return file;
}
