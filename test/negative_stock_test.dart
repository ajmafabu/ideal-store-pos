import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/product.dart';

void main() {
  test('a stock below zero (sold before the purchase was entered) is worth nothing, not a minus', () {
    expect(Product(id: 'a', name: 'x', stock: -12, purchasePrice: 8).stockOnHand, 0);
    expect(Product(id: 'a', name: 'x', stock: 88, purchasePrice: 8).stockOnHand, 88);
    // and it shows as out of stock, not low stock
    final p = Product(id: 'a', name: 'x', stock: -3, lowStockAlert: 10);
    expect(p.isLowStock, isFalse);
    expect(p.stock, -3);
  });
}
