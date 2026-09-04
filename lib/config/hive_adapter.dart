import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

class HiveAdapter {
  static const String pendingSalesBox = 'pending_sales';
  static const String cachedSalesBox = 'cached_sales';
  static const String pendingOpsBox = 'pending_operations';
  static const String cachedProductsBox = 'cached_products';
  static const String cachedCustomersBox = 'cached_customers';
  static const String cachedPurchasesBox = 'cached_purchases';
  static const String cachedExpensesBox = 'cached_expenses';
  static const String cachedSuppliersBox = 'cached_suppliers';
  static const String cachedReturnsBox = 'cached_returns';
  static const String cachedDamagedBox = 'cached_damaged';
  static const String cachedAccountsBox = 'cached_accounts';
  static const String pendingWritesBox = 'pending_writes';
  static const String heldBillsBox = 'held_bills';
  static const String pendingAuditBox = 'pending_audit';

  static HiveAesCipher? _currentCipher;

  static HiveAesCipher get cipher {
    if (_currentCipher == null) {
      final fallbackKey = Uint8List.fromList(List.filled(32, 0x42));
      _currentCipher = HiveAesCipher(fallbackKey);
    }
    return _currentCipher!;
  }

  static Future<Uint8List> _getOrCreateKey() async {
    final dir = await getApplicationDocumentsDirectory();
    final keyFile = File('${dir.path}/.hive_key');

    if (await keyFile.exists()) {
      final encoded = await keyFile.readAsString();
      return base64Url.decode(encoded);
    }

    final random = Random.secure();
    final key = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await keyFile.writeAsString(base64Url.encode(key));
    return key;
  }

  static Future<void> init() async {
    _currentCipher = HiveAesCipher(await _getOrCreateKey());
    final cipher = _currentCipher!;

    Future<Box<Map>> openEncryptedBox(String name) async {
      try {
        return await Hive.openBox<Map>(name, encryptionCipher: cipher);
      } catch (e) {
        try {
          if (Hive.isBoxOpen(name)) {
            final box = Hive.box<Map>(name);
            await box.close();
          }
        } catch (_) {}
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
        try {
          return await Hive.openBox<Map>(name, encryptionCipher: cipher);
        } catch (e2) {
          rethrow;
        }
      }
    }

    _pendingSalesBox = await openEncryptedBox(pendingSalesBox);
    _cachedSalesBox = await openEncryptedBox(cachedSalesBox);
    _pendingOpsBox = await openEncryptedBox(pendingOpsBox);
    _cachedProductsBox = await openEncryptedBox(cachedProductsBox);
    _cachedCustomersBox = await openEncryptedBox(cachedCustomersBox);
    _cachedPurchasesBox = await openEncryptedBox(cachedPurchasesBox);
    _cachedExpensesBox = await openEncryptedBox(cachedExpensesBox);
    _cachedSuppliersBox = await openEncryptedBox(cachedSuppliersBox);
    _cachedReturnsBox = await openEncryptedBox(cachedReturnsBox);
    _cachedDamagedBox = await openEncryptedBox(cachedDamagedBox);
    _cachedAccountsBox = await openEncryptedBox(cachedAccountsBox);
    _pendingWritesBox = await openEncryptedBox(pendingWritesBox);
    _heldBillsBox = await openEncryptedBox(heldBillsBox);
    _pendingAuditBox = await openEncryptedBox(pendingAuditBox);
  }

  static late Box<Map> _pendingSalesBox;
  static late Box<Map> _cachedSalesBox;
  static late Box<Map> _pendingOpsBox;
  static late Box<Map> _cachedProductsBox;
  static late Box<Map> _cachedCustomersBox;
  static late Box<Map> _cachedPurchasesBox;
  static late Box<Map> _cachedExpensesBox;
  static late Box<Map> _cachedSuppliersBox;
  static late Box<Map> _cachedReturnsBox;
  static late Box<Map> _cachedDamagedBox;
  static late Box<Map> _cachedAccountsBox;
  static late Box<Map> _pendingWritesBox;
  static late Box<Map> _heldBillsBox;
  static late Box<Map> _pendingAuditBox;

  static Box<Map> get pendingSalesBox_ => _pendingSalesBox;
  static Box<Map> get cachedSalesBox_ => _cachedSalesBox;
  static Box<Map> get pendingOpsBox_ => _pendingOpsBox;
  static Box<Map> get cachedProductsBox_ => _cachedProductsBox;
  static Box<Map> get cachedCustomersBox_ => _cachedCustomersBox;
  static Box<Map> get cachedPurchasesBox_ => _cachedPurchasesBox;
  static Box<Map> get cachedExpensesBox_ => _cachedExpensesBox;
  static Box<Map> get cachedSuppliersBox_ => _cachedSuppliersBox;
  static Box<Map> get cachedReturnsBox_ => _cachedReturnsBox;
  static Box<Map> get cachedDamagedBox_ => _cachedDamagedBox;
  static Box<Map> get cachedAccountsBox_ => _cachedAccountsBox;
  static Box<Map> get pendingWritesBox_ => _pendingWritesBox;
  static Box<Map> get heldBillsBox_ => _heldBillsBox;
  static Box<Map> get pendingAuditBox_ => _pendingAuditBox;
}
