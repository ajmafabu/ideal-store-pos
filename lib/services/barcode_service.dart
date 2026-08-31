import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class BarcodeProduct {
  final String name;
  final String brand;
  final String category;
  final String barcode;
  final String? mrp;

  BarcodeProduct({
    required this.name,
    required this.brand,
    required this.category,
    required this.barcode,
    this.mrp,
  });
}

class BarcodeService {
  static Map<String, Map<String, String>>? _localDb;

  static Future<Map<String, Map<String, String>>> _loadLocalDb() async {
    if (_localDb != null) return _localDb!;
    try {
      final jsonStr = await rootBundle.loadString('lib/data/indian_products.json');
      final data = json.decode(jsonStr);
      final products = data['products'] as List;
      _localDb = {};
      for (final p in products) {
        final barcode = p['barcode'] as String?;
        if (barcode != null && barcode.isNotEmpty) {
          _localDb![barcode] = {
            'name': p['name'] as String? ?? '',
            'brand': p['brand'] as String? ?? '',
            'category': p['category'] as String? ?? 'Other',
          };
        }
      }
    } catch (e) {
      _localDb = {};
    }
    return _localDb!;
  }

  static Future<BarcodeProduct?> lookup(String barcode) async {
    // 1. Local Indian FMCG database (instant, offline)
    final localResult = await _lookupLocal(barcode);
    if (localResult != null) return localResult;

    // 2. Open Food Facts (free, no key, good for global food products)
    final offResult = await _lookupOpenFoodFacts(barcode);
    if (offResult != null) return offResult;

    // 3. UPCitemdb (free trial, good global coverage)
    final upcResult = await _lookupUPCitemdb(barcode);
    if (upcResult != null) return upcResult;

    // 4. Barcode Lookup (trial)
    final barcodeLookupResult = await _lookupBarcodeLookup(barcode);
    if (barcodeLookupResult != null) return barcodeLookupResult;

    return null;
  }

  static Future<BarcodeProduct?> _lookupLocal(String barcode) async {
    try {
      final db = await _loadLocalDb();
      final product = db[barcode];
      if (product == null) return null;

      return BarcodeProduct(
        name: product['name']!,
        brand: product['brand']!,
        category: product['category']!,
        barcode: barcode,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<BarcodeProduct?> _lookupOpenFoodFacts(String barcode) async {
    try {
      final url = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$barcode.json');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['status'] != 1 || data['product'] == null) return null;

      final product = data['product'];
      final name = product['product_name'] as String? ?? '';
      final brands = product['brands'] as String? ?? '';
      final categories = product['categories'] as String? ?? '';

      if (name.isEmpty) return null;

      return BarcodeProduct(
        name: name,
        brand: brands,
        category: categories.isNotEmpty ? categories.split(',').first.trim() : 'Food & Beverages',
        barcode: barcode,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<BarcodeProduct?> _lookupUPCitemdb(String barcode) async {
    try {
      final url = Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['items'] == null || (data['items'] as List).isEmpty) return null;

      final item = data['items'][0];
      final title = item['title'] as String? ?? '';
      final brand = item['brand'] as String? ?? '';
      final category = item['category'] as String? ?? '';

      if (title.isEmpty) return null;

      return BarcodeProduct(
        name: title,
        brand: brand,
        category: category.isNotEmpty ? category : 'Other',
        barcode: barcode,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<BarcodeProduct?> _lookupBarcodeLookup(String barcode) async {
    try {
      final url = Uri.parse('https://api.barcodelookup.com/v3/products?barcode=$barcode&formatted=y&key=trial');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['products'] == null || (data['products'] as List).isEmpty) return null;

      final product = data['products'][0];
      final title = product['title'] as String? ?? '';
      final brand = product['brand'] as String? ?? '';
      final category = product['category'] as String? ?? '';
      final price = product['price'] as String? ?? product['msrp'] as String? ?? '';

      if (title.isEmpty) return null;

      return BarcodeProduct(
        name: title,
        brand: brand,
        category: category.isNotEmpty ? category : 'Other',
        barcode: barcode,
        mrp: price.isNotEmpty ? price : null,
      );
    } catch (e) {
      return null;
    }
  }
}
