import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/hive_adapter.dart';
import '../models/sale.dart';
import '../utils/logger.dart';
import '../utils/network_errors.dart';
import 'audit_service.dart';

import 'package:hive_ce/hive.dart';

/// Local cache + offline queue.
///
/// Since app 1.1.0 the queue is replayed in a fixed order (plain writes such
/// as new customers, then sales, then edits/deletes/returns), one item at a
/// time, through the same database functions the online path uses, with the
/// same ids — so every replay is idempotent. Items that keep failing are
/// moved to a "needs review" list instead of being deleted (#5, #6).
class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;
  OfflineService._internal();

  late Box<Map> _pendingBox;
  late Box<Map> _salesBox;
  late Box<Map> _pendingOpsBox;
  late Box<Map> _productsBox;
  late Box<Map> _customersBox;
  late Box<Map> _purchasesBox;
  late Box<Map> _expensesBox;
  late Box<Map> _suppliersBox;
  late Box<Map> _returnsBox;
  late Box<Map> _damagedBox;
  late Box<Map> _accountsBox;
  late Box<Map> _pendingWritesBox;
  late Box<Map> _heldBillsBox;
  late Box<Map> _deadLetterBox;
  bool _initialized = false;

  static const int maxRetries = 5;

  Future<void> init() async {
    if (_initialized) return;
    final cipher = HiveAdapter.cipher;
    Future<Box<Map>> open(String name) => Hive.openBox<Map>(name, encryptionCipher: cipher);
    _pendingBox = await open(HiveAdapter.pendingSalesBox);
    _salesBox = await open(HiveAdapter.cachedSalesBox);
    _pendingOpsBox = await open(HiveAdapter.pendingOpsBox);
    _productsBox = await open(HiveAdapter.cachedProductsBox);
    _customersBox = await open(HiveAdapter.cachedCustomersBox);
    _purchasesBox = await open(HiveAdapter.cachedPurchasesBox);
    _expensesBox = await open(HiveAdapter.cachedExpensesBox);
    _suppliersBox = await open(HiveAdapter.cachedSuppliersBox);
    _returnsBox = await open(HiveAdapter.cachedReturnsBox);
    _damagedBox = await open(HiveAdapter.cachedDamagedBox);
    _accountsBox = await open(HiveAdapter.cachedAccountsBox);
    _pendingWritesBox = await open(HiveAdapter.pendingWritesBox);
    _heldBillsBox = await open(HiveAdapter.heldBillsBox);
    _deadLetterBox = await open(HiveAdapter.deadLetterBox);
    _initialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await init();
  }

  bool get isReady => _initialized;

  Box<Map> get pendingBox => _pendingBox;
  Box<Map> get productsBox => _productsBox;
  Box<Map> get customersBox => _customersBox;

  int get pendingCount => _initialized ? _pendingBox.length : 0;
  int get pendingOpsCount => _initialized ? _pendingOpsBox.length : 0;
  int get pendingWritesCount => _initialized ? _pendingWritesBox.length : 0;
  int get deadLetterCount => _initialized ? _deadLetterBox.length : 0;

  int getConflictCount() => deadLetterCount;

  // ========== CACHES ==========

  Future<void> _replaceBox(Box<Map> box, List<Map<String, dynamic>> rows, String label) async {
    await _ensureInitialized();
    await box.clear();
    await box.putAll({for (final r in rows) r['id'].toString(): r});
    await box.flush();
    Logger.info('Cached ${rows.length} $label');
  }

  List<Map<String, dynamic>> _all(Box<Map> box) =>
      _initialized ? box.values.map((e) => Map<String, dynamic>.from(e)).toList() : [];

  Future<void> cacheProducts(List<Map<String, dynamic>> products) => _replaceBox(_productsBox, products, 'products');
  List<Map<String, dynamic>> getCachedProducts() => _all(_productsBox);
  Map<String, dynamic>? getCachedProduct(String id) {
    if (!_initialized) return null;
    final data = _productsBox.get(id);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  Future<void> cacheCustomers(List<Map<String, dynamic>> customers) => _replaceBox(_customersBox, customers, 'customers');
  List<Map<String, dynamic>> getCachedCustomers() => _all(_customersBox);

  Future<void> cachePurchases(List<Map<String, dynamic>> purchases) => _replaceBox(_purchasesBox, purchases, 'purchases');
  List<Map<String, dynamic>> getCachedPurchases() => _all(_purchasesBox);

  Future<void> addCachedPurchase(Map<String, dynamic> purchase) async {
    await _ensureInitialized();
    final id = purchase['id'] as String? ?? newDocumentId();
    purchase['id'] = id;
    await _purchasesBox.put(id, purchase);
    await _purchasesBox.flush();
  }

  Future<void> removeCachedPurchase(String id) async {
    await _ensureInitialized();
    await _purchasesBox.delete(id);
    await _purchasesBox.flush();
  }

  List<Map<String, dynamic>> getPendingPurchases() {
    if (!_initialized) return [];
    return _pendingWritesBox.values
        .where((w) => w['table'] == 'purchases' && w['operation'] == 'insert')
        .map((w) => Map<String, dynamic>.from(w['data'] as Map))
        .toList();
  }

  Future<void> cacheExpenses(List<Map<String, dynamic>> expenses) => _replaceBox(_expensesBox, expenses, 'expenses');
  List<Map<String, dynamic>> getCachedExpenses() => _all(_expensesBox);

  Future<void> cacheSuppliers(List<Map<String, dynamic>> suppliers) => _replaceBox(_suppliersBox, suppliers, 'suppliers');
  List<Map<String, dynamic>> getCachedSuppliers() => _all(_suppliersBox);

  Future<void> cacheReturns(List<Map<String, dynamic>> returns) => _replaceBox(_returnsBox, returns, 'returns');
  List<Map<String, dynamic>> getCachedReturns() => _all(_returnsBox);

  Future<void> cacheDamaged(List<Map<String, dynamic>> damaged) => _replaceBox(_damagedBox, damaged, 'damaged items');
  List<Map<String, dynamic>> getCachedDamaged() => _all(_damagedBox);

  Future<void> cacheAccounts(List<Map<String, dynamic>> accounts) => _replaceBox(_accountsBox, accounts, 'accounts');
  List<Map<String, dynamic>> getCachedAccounts() => _all(_accountsBox);

  Future<void> cacheSalesHistory(List<Map<String, dynamic>> sales) => _replaceBox(_salesBox, sales, 'sales');
  List<Map<String, dynamic>> getCachedSalesHistory() {
    final sales = _all(_salesBox);
    sales.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    return sales;
  }

  // ========== PENDING WRITES (generic offline queue) ==========

  Future<void> queuePendingWrite(Map<String, dynamic> op) async {
    await _ensureInitialized();
    final key = DateTime.now().microsecondsSinceEpoch.toString();
    op['id'] = key;
    op['timestamp'] = DateTime.now().toUtc().toIso8601String();
    op['retry_count'] = 0;
    op['last_error'] = null;
    final data = op['data'];
    if (data is Map && op['operation'] == 'insert' && !isUuid(data['id']?.toString())) {
      data['id'] = newDocumentId();          // stable id → idempotent replay
    }
    await _pendingWritesBox.put(key, op);
    Logger.info('Queued pending write: ${op['operation']} on ${op['table']}');
  }

  List<Map<String, dynamic>> getPendingWrites() {
    final writes = _all(_pendingWritesBox);
    writes.sort((a, b) => (a['timestamp'] ?? '').toString().compareTo((b['timestamp'] ?? '').toString()));
    return writes;
  }

  Future<void> removePendingWrite(String id) async {
    await _ensureInitialized();
    await _pendingWritesBox.delete(id);
  }

  Future<void> clearPendingWrites() async {
    await _ensureInitialized();
    await _pendingWritesBox.clear();
  }

  // ========== OFFLINE SALES ==========

  Future<void> saveSaleOffline(Map<String, dynamic> saleData) async {
    await _ensureInitialized();
    var id = saleData['id']?.toString() ?? '';
    if (!isUuid(id)) {
      id = newDocumentId();
      saleData['id'] = id;
    }
    saleData['created_at'] ??= DateTime.now().toUtc().toIso8601String();
    saleData['retry_count'] = 0;
    saleData['last_error'] = null;
    await _pendingBox.put(id, saleData);
    await _salesBox.put(id, saleData);          // visible in history at once
    Logger.info('Sale saved offline: $id');
  }

  List<Map<String, dynamic>> getPendingSales() => _all(_pendingBox);

  /// Moves everything still queued to the review list (nothing is lost).
  Future<void> clearAllPending() async {
    await _ensureInitialized();
    for (final s in getPendingSales()) {
      await _toDeadLetter('sale', s, 'Cleared by user');
    }
    for (final o in getPendingOperations()) {
      await _toDeadLetter('op', o, 'Cleared by user');
    }
    for (final w in getPendingWrites()) {
      await _toDeadLetter('write', w, 'Cleared by user');
    }
    await _pendingBox.clear();
    await _pendingOpsBox.clear();
    await _pendingWritesBox.clear();
    lastSyncError = null;
  }

  Future<void> removePendingSale(String id) async {
    await _ensureInitialized();
    await _pendingBox.delete(id);
  }

  // ========== PENDING OPERATIONS (edit/delete/return/damaged) ==========

  Future<void> addPendingOperation(Map<String, dynamic> op) async {
    await _ensureInitialized();
    final key = DateTime.now().microsecondsSinceEpoch.toString();
    op['id'] = key;
    op['timestamp'] = DateTime.now().toUtc().toIso8601String();
    op['retry_count'] = 0;
    op['last_error'] = null;
    await _pendingOpsBox.put(key, op);
    Logger.info('Queued operation: ${op['type']}');
  }

  List<Map<String, dynamic>> getPendingOperations() {
    final ops = _all(_pendingOpsBox);
    ops.sort((a, b) => (a['timestamp'] ?? '').toString().compareTo((b['timestamp'] ?? '').toString()));
    return ops;
  }

  Future<void> removePendingOperation(String id) async {
    await _ensureInitialized();
    await _pendingOpsBox.delete(id);
  }

  void applyEditToLocalCache(String saleId, Map<String, dynamic> updatedSale) {
    if (!_initialized) return;
    final existing = _salesBox.get(saleId);
    final merged = <String, dynamic>{
      if (existing != null) ...Map<String, dynamic>.from(existing),
      ...updatedSale,
      'id': saleId,
    };
    _salesBox.put(saleId, merged);
  }

  void applyDeleteToLocalCache(String saleId) {
    if (!_initialized) return;
    _salesBox.delete(saleId);
  }

  // ========== NEEDS REVIEW (dead letters, #6) ==========

  Future<void> _toDeadLetter(String kind, Map<String, dynamic> item, String error) async {
    final key = '${kind}_${DateTime.now().microsecondsSinceEpoch}';
    await _deadLetterBox.put(key, {
      'key': key,
      'kind': kind,
      'item': jsonDecode(jsonEncode(item)),
      'error': error,
      'failed_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  List<Map<String, dynamic>> getDeadLetters() {
    final list = _all(_deadLetterBox);
    list.sort((a, b) => (b['failed_at'] ?? '').toString().compareTo((a['failed_at'] ?? '').toString()));
    return list;
  }

  /// Puts a reviewed item back in the queue for another try.
  Future<void> retryDeadLetter(String key) async {
    await _ensureInitialized();
    final raw = _deadLetterBox.get(key);
    if (raw == null) return;
    final kind = raw['kind'] as String;
    final item = Map<String, dynamic>.from(raw['item'] as Map);
    item['retry_count'] = 0;
    item['last_error'] = null;
    switch (kind) {
      case 'sale':
        await _pendingBox.put(item['id'].toString(), item);
        break;
      case 'op':
        await _pendingOpsBox.put(item['id'].toString(), item);
        break;
      default:
        await _pendingWritesBox.put(item['id'].toString(), item);
    }
    await _deadLetterBox.delete(key);
  }

  Future<void> discardDeadLetter(String key) async {
    await _ensureInitialized();
    await _deadLetterBox.delete(key);
  }

  // ========== SYNC ==========

  String? lastSyncError;
  bool _isSyncing = false;

  Future<bool> syncPendingSales() async {
    await _ensureInitialized();
    if (_isSyncing) return false;
    _isSyncing = true;
    try {
      return await _syncAll();
    } finally {
      _isSyncing = false;
    }
  }

  /// Handles a failed item: a network failure stops this sync round (the
  /// item stays queued untouched); any other failure counts as a retry and
  /// after [maxRetries] the item moves to the review list.
  /// Returns false when the round should stop.
  Future<bool> _onFailure(Box<Map> box, String kind, Map<String, dynamic> item, Object e) async {
    lastSyncError = serverMessage(e);
    if (isNetworkError(e)) return false;
    final retries = ((item['retry_count'] as num?)?.toInt() ?? 0) + 1;
    item['retry_count'] = retries;
    item['last_error'] = lastSyncError;
    final key = item['id'].toString();
    if (retries >= maxRetries) {
      Logger.error('Sync gave up on $kind $key after $retries tries: $e');
      await _toDeadLetter(kind, item, lastSyncError ?? e.toString());
      await box.delete(key);
    } else {
      await box.put(key, item);
    }
    return true;
  }

  Future<bool> _syncAll() async {
    final writes = getPendingWrites();
    final sales = getPendingSales();
    final ops = getPendingOperations();
    if (writes.isEmpty && sales.isEmpty && ops.isEmpty) {
      lastSyncError = null;
      return true;
    }
    Logger.info('Sync: ${writes.length} writes, ${sales.length} sales, ${ops.length} operations');
    final supabase = Supabase.instance.client;
    var allSynced = true;
    lastSyncError = null;

    // 1. plain writes first (customers/products created offline are
    //    referenced by the sales that follow)
    for (final write in writes) {
      try {
        await _syncSingleWrite(supabase, write);
        await removePendingWrite(write['id'].toString());
        final data = write['data'];
        if (write['table'] == 'purchases' && data is Map && data['id'] != null) {
          await removeCachedPurchase(data['id'].toString());
        }
      } catch (e) {
        allSynced = false;
        if (!await _onFailure(_pendingWritesBox, 'write', write, e)) return false;
      }
    }

    // 2. sales, oldest first, each with its own stable id
    final orderedSales = [...sales]
      ..sort((a, b) => (a['created_at'] ?? '').toString().compareTo((b['created_at'] ?? '').toString()));
    for (final sale in orderedSales) {
      try {
        await _syncSale(supabase, sale);
        await removePendingSale(sale['id'].toString());
      } catch (e) {
        allSynced = false;
        if (!await _onFailure(_pendingBox, 'sale', sale, e)) return false;
      }
    }

    // 3. edits / deletes / returns / damaged — through the same RPCs
    for (final op in ops) {
      try {
        await _syncOperation(supabase, op);
        await removePendingOperation(op['id'].toString());
      } catch (e) {
        allSynced = false;
        if (!await _onFailure(_pendingOpsBox, 'op', op, e)) return false;
      }
    }

    if (allSynced) {
      try {
        final response = await supabase.from('sales').select().order('created_at', ascending: false).limit(200);
        await cacheSalesHistory(List<Map<String, dynamic>>.from(response as List));
      } catch (e) {
        Logger.warning('Failed to refresh sales cache after sync');
      }
    }
    return allSynced;
  }

  /// Deterministic UUID for sales queued by app versions before 1.1.0,
  /// which used millisecond timestamps as ids: retries stay idempotent.
  static String _legacyIdToUuid(String legacyId) {
    final h = sha256.convert(utf8.encode('ideal-store-pos-sale:$legacyId')).toString();
    final variant = ((int.parse(h[16], radix: 16) & 0x3) | 0x8).toRadixString(16);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-5${h.substring(13, 16)}-$variant${h.substring(17, 20)}-${h.substring(20, 32)}';
  }

  Future<void> _syncSale(SupabaseClient supabase, Map<String, dynamic> stored) async {
    final data = Map<String, dynamic>.from(stored);
    if (!isUuid(data['id']?.toString())) {
      data['id'] = _legacyIdToUuid(data['id'].toString());
    }
    final sale = Sale.fromJson(data);
    final payload = sale.toInsertJson();
    // a customer that never reached the server cannot be referenced
    if (payload['customer_id'] != null && !isUuid(payload['customer_id'] as String)) {
      payload['customer_id'] = null;
    }
    try {
      await supabase.from('sales').insert(payload);
    } catch (e) {
      if (isDuplicateKey(e)) return;        // the first attempt did commit
      rethrow;
    }
    Logger.info('Synced sale ${sale.id}');
  }

  Future<void> _syncOperation(SupabaseClient supabase, Map<String, dynamic> op) async {
    final type = op['type'] as String? ?? '';
    switch (type) {
      case 'delete':
        try {
          await supabase.rpc('delete_sale_atomic', params: {'p_sale_id': op['sale_id']});
        } on PostgrestException catch (e) {
          if (e.code != 'P0002') rethrow;   // already gone
        }
        break;
      case 'edit':
        final params = op['params'];
        if (params is! Map) {
          // queued by an old app version as a plain UPDATE — unsafe to replay
          throw Exception('Old-format edit: please redo this edit from Sales history');
        }
        await supabase.rpc('edit_sale_atomic', params: Map<String, dynamic>.from(params));
        break;
      case 'return':
        final d = Map<String, dynamic>.from(op['data'] as Map);
        await supabase.rpc('create_return_atomic', params: {
          'p_id': d['id'],
          'p_product_id': d['product_id'],
          'p_sale_id': d['original_sale_id'] ?? d['sale_id'],
          'p_product_name': d['product_name'],
          'p_quantity': d['quantity'],
          'p_reason': d['reason'],
          'p_refund_method': d['refund_method'],
        });
        break;
      case 'damaged':
        final d = Map<String, dynamic>.from(op['data'] as Map);
        await supabase.rpc('create_damaged_atomic', params: {
          'p_id': d['id'],
          'p_product_id': d['product_id'],
          'p_product_name': d['product_name'],
          'p_quantity': d['quantity'],
          'p_reason': d['reason'],
        });
        break;
      default:
        throw Exception('Unknown queued operation "$type"');
    }
  }

  Future<void> _syncSingleWrite(SupabaseClient supabase, Map<String, dynamic> write) async {
    final table = write['table'] as String;
    final operation = write['operation'] as String;
    final data = Map<String, dynamic>.from(write['data'] as Map);

    switch (operation) {
      case 'insert':
        // returns and damaged entries have stock effects: replay via RPC
        if (table == 'product_returns') {
          await _syncOperation(supabase, {'type': 'return', 'data': data});
          return;
        }
        if (table == 'damaged_products') {
          await _syncOperation(supabase, {'type': 'damaged', 'data': data});
          return;
        }
        if (table == 'account_transactions') {
          data['source'] ??= 'manual';
        }
        if (!isUuid(data['id']?.toString())) data.remove('id');
        try {
          await supabase.from(table).insert(data);
        } catch (e) {
          if (isDuplicateKey(e)) return;   // already synced on an earlier attempt
          rethrow;
        }
        break;
      case 'update':
        final id = data.remove('id').toString();
        if (!isUuid(id)) throw Exception('Cannot update a record that was never synced');
        await supabase.from(table).update(data).eq('id', id);
        break;
      case 'delete':
        final id = data['id'].toString();
        if (!isUuid(id)) return;
        await supabase.from(table).delete().eq('id', id);
        break;
      case 'stock_add':
      case 'stock_deduct':
        // queued by app versions before 1.1.0; the database now adjusts
        // stock as part of the purchase/sale insert itself
        Logger.info('Skipping legacy $operation (handled by the database)');
        break;
      default:
        throw Exception('Unknown queued write "$operation"');
    }
  }

  /// Reachability check used by the UI and the sync loop. Reads one row of
  /// app_config (tiny, readable before login).
  Future<bool> isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!results.any((r) => r != ConnectivityResult.none)) return false;
      await Supabase.instance.client
          .from('app_config')
          .select('key')
          .limit(1)
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> forceSync() async {
    final result = await syncPendingSales();
    try {
      await AuditService().syncPendingAuditLogs();
    } catch (_) {}
    return result;
  }

  // ===== HELD BILLS =====
  Future<void> saveHeldBills(List<Map<String, dynamic>> bills) async {
    await _ensureInitialized();
    await _heldBillsBox.clear();
    for (int i = 0; i < bills.length; i++) {
      await _heldBillsBox.put('bill_$i', Map<String, dynamic>.from(bills[i]));
    }
  }

  List<Map<String, dynamic>> getHeldBills() {
    if (!_initialized) return [];
    return _heldBillsBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> clearHeldBills() async {
    await _ensureInitialized();
    await _heldBillsBox.clear();
  }
}
