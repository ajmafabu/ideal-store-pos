import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:ideal_store_pos/utils/product_search.dart';

Product _p(String name, {String? tamil, String? barcode}) => Product(
      id: name,
      name: name,
      tamilName: tamil,
      barcode: barcode,
      purchasePrice: 1,
      sellingPrice: 2,
      stock: 1,
    );

void main() {
  final all = [
    _p('comfort kosupathi'),
    _p('all rounder sunfeast'),
    _p('SUGAR BANNARI 1 kg'),
    _p('bangali sukku coffie'),
    _p('dettol 10 rs', barcode: '8901396602071'),
    _p('dettol 20 rs'),
    _p('hamam 10 rs soap', tamil: 'ஹமாம்'),
  ];
  List<String> names(String q) => searchProducts(all, q).map((p) => p.name).toList();

  test('starts-with first, then word start, then contains', () {
    expect(names('su'), [
      'SUGAR BANNARI 1 kg', // starts with "su"
      'all rounder sunfeast', // a word starts with "su"
      'bangali sukku coffie',
      'comfort kosupathi', // only contains "su"
    ]);
  });

  test('every word must match: "dettol 10" finds only the 10 rs pack', () {
    expect(names('dettol 10'), ['dettol 10 rs']);
  });

  test('a scanned barcode comes first', () {
    expect(names('8901396602071').first, 'dettol 10 rs');
  });

  test('Tamil name search', () {
    expect(names('ஹமாம்'), ['hamam 10 rs soap']);
  });

  test('empty search shows nothing', () {
    expect(names('  '), isEmpty);
  });
}
