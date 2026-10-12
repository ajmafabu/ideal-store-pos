import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:ideal_store_pos/services/product_gst_export.dart';

void main() {
  test('GST sheet: header, sorted by category then name, no cost price', () {
    final rows = productGstSheetRows([
      Product(id: 'b', name: 'Sugar', category: 'Grocery', purchasePrice: 40, sellingPrice: 45, stock: 1, gstRate: 5, hsnCode: '1701'),
      Product(id: 'a', name: 'Bread', category: 'Bakery', purchasePrice: 30, sellingPrice: 35, stock: 1),
      Product(id: 'c', name: 'Atta', category: 'Grocery', purchasePrice: 50, sellingPrice: 55, stock: 1),
    ]);
    expect(rows.first, productGstSheetHeader);
    expect(rows.skip(1).map((r) => r[1]), ['Bread', 'Atta', 'Sugar']);
    expect(rows[3].sublist(7), ['1701', 5]);
    expect(rows.expand((r) => r), isNot(contains(40.0)));
  });
}
