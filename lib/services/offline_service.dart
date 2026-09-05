import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/hive_adapter.dart';
import '../utils/logger.dart';
import 'account_service.dart';
import 'audit_service.dart';

import 'package:hive_ce/hive.dart';

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
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final cipher = HiveAdapter.cipher;
    _pendingBox = await Hive.openBox<Map>(HiveAdapter.pendingSalesBox, encryptionCipher: cipher);
    _salesBox = await Hive.openBox<Map>(HiveAdapter.cachedSalesBox, encryptionCipher: cipher);
    _pendingOpsBox = await Hive.openBox<Map>(HiveAdapter.pendingOpsBox, encryptionCipher: cipher);
    _productsBox = await Hive.openBox<Map>(HiveAdapter.cachedProductsBox, encryptionCipher: cipher);
    _customersBox = await Hive.openBox<Map>(HiveAdapter.cachedCustomersBox, encryptionCipher: cipher);
    _purchasesBox = await Hive.openBox<Map>(HiveAdapter.cachedPurchasesBox, encryptionCipher: cipher);
    _expensesBox = await Hive.openBox<Map>(HiveAdapter.cachedExpensesBox, encryptionCipher: cipher);
    _suppliersBox = await Hive.openBox<Map>(HiveAdapter.cachedSuppliersBox, encryptionCipher: cipher);
    _returnsBox = await Hive.openBox<Map>(HiveAdapter.cachedReturnsBox, encryptionCipher: cipher);
    _damagedBox = await Hive.openBox<Map>(HiveAdapter.cachedDamagedBox, encryptionCipher: cipher);
    _accountsBox = await Hive.openBox<Map>(HiveAdapter.cachedAccountsBox, encryptionCipher: cipher);
    _pendingWritesBox = await Hive.openBox<Map>(HiveAdapter.pendingWritesBox, encryptionCipher: cipher);
    _heldBillsBox = await Hive.openBox<Map>(HiveAdapter.heldBillsBox, encryptionCipher: cipher);
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

  int getConflictCount() {
    if (!_initialized) return 0;
    // Count pending ops that are edits (potential conflicts)
    int count = 0;
    for (final op in _pendingOpsBox.values) {
      if (op['type'] == 'edit') count++;
    }
    return count;
  }

  // ========== PRODUCT CACHING ==========

  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    await _ensureInitialized();
    await _productsBox.clear();
    for (final product in products) {
      final id = product['id'] as String;
      _productsBox.put(id, product);
    }
    await _productsBox.flush();
    Logger.info('Cached ${products.length} products');
  }

  List<Map<String, dynamic>> getCachedProducts() {
    if (!_initialized) return [];
    return _productsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic>? getCachedProduct(String id) {
    if (!_initialized) return null;
    final data = _productsBox.get(id);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  // ========== CUSTOMER CACHING ==========

  Future<void> cacheCustomers(List<Map<String, dynamic>> customers) async {
    await _ensureInitialized();
    await _customersBox.clear();
    for (final customer in customers) {
      final id = customer['id'] as String;
      _customersBox.put(id, customer);
    }
    await _customersBox.flush();
    Logger.info('Cached ${customers.length} customers');
  }

  List<Map<String, dynamic>> getCachedCustomers() {
    if (!_initialized) return [];
    return _customersBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ========== PURCHASE CACHING ==========

  Future<void> cachePurchases(List<Map<String, dynamic>> purchases) async {
    await _ensureInitialized();
    await _purchasesBox.clear();
    for (final purchase in purchases) {
      final id = purchase['id'] as String;
      _purchasesBox.put(id, purchase);
    }
    await _purchasesBox.flush();
    Logger.info('Cached ${purchases.length} purchases');
  }

  List<Map<String, dynamic>> getCachedPurchases() {
    if (!_initialized) return [];
    return _purchasesBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> addCachedPurchase(Map<String, dynamic> purchase) async {
    await _ensureInitialized();
    final id = purchase['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString();
    purchase['id'] = id;
    await _purchasesBox.put(id, purchase);
    await _purchasesBox.flush();
    Logger.info('Cached offline purchase: $id');
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

  // ========== EXPENSE CACHING ==========

  Future<void> cacheExpenses(List<Map<String, dynamic>> expenses) async {
    await _ensureInitialized();
    await _expensesBox.clear();
    for (final expense in expenses) {
      final id = expense['id'] as String;
      _expensesBox.put(id, expense);
    }
    await _expensesBox.flush();
    Logger.info('Cached ${expenses.length} expenses');
  }

  List<Map<String, dynamic>> getCachedExpenses() {
    if (!_initialized) return [];
    return _expensesBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ========== SUPPLIER CACHING ==========

  Future<void> cacheSuppliers(List<Map<String, dynamic>> suppliers) async {
    await _ensureInitialized();
    await _suppliersBox.clear();
    for (final supplier in suppliers) {
      final id = supplier['id'] as String;
      _suppliersBox.put(id, supplier);
    }
    await _suppliersBox.flush();
    Logger.info('Cached ${suppliers.length} suppliers');
  }

  List<Map<String, dynamic>> getCachedSuppliers() {
    if (!_initialized) return [];
    return _suppliersBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ========== RETURNS CACHING ==========

  Future<void> cacheReturns(List<Map<String, dynamic>> returns) async {
    await _ensureInitialized();
    await _returnsBox.clear();
    for (final r in returns) {
      final id = r['id'] as String;
      _returnsBox.put(id, r);
    }
    await _returnsBox.flush();
    Logger.info('Cached ${returns.length} returns');
  }

  List<Map<String, dynamic>> getCachedReturns() {
    if (!_initialized) return [];
    return _returnsBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ========== DAMAGED CACHING ==========

  Future<void> cacheDamaged(List<Map<String, dynamic>> damaged) async {
    await _ensureInitialized();
    await _damagedBox.clear();
    for (final d in damaged) {
      final id = d['id'] as String;
      _damagedBox.put(id, d);
    }
    await _damagedBox.flush();
    Logger.info('Cached ${damaged.length} damaged items');
  }

  List<Map<String, dynamic>> getCachedDamaged() {
    if (!_initialized) return [];
    return _damagedBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ========== ACCOUNTS CACHING ==========

  Future<void> cacheAccounts(List<Map<String, dynamic>> accounts) async {
    await _ensureInitialized();
    await _accountsBox.clear();
    for (final a in accounts) {
      final id = a['id'] as String;
      _accountsBox.put(id, a);
    }
    await _accountsBox.flush();
    Logger.info('Cached ${accounts.length} accounts');
  }

  List<Map<String, dynamic>> getCachedAccounts() {
    if (!_initialized) return [];
    return _accountsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ========== PENDING WRITES (offline queue for any operation) ==========

  Future<void> queuePendingWrite(Map<String, dynamic> op) async {
    await _ensureInitialized();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    op['id'] = id;
    op['timestamp'] = DateTime.now().toIso8601String();
    op['synced'] = false;
    op['retry_count'] = 0;
    op['last_error'] = null;
    await _pendingWritesBox.put(id, op);
    Logger.info('Queued pending write: ${op['type']} for ${op['table']}');
  }

  List<Map<String, dynamic>> getPendingWrites() {
    if (!_initialized) return [];
    final writes = _pendingWritesBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    writes.sort(
      (a, b) => (a['timestamp'] ?? '').toString().compareTo(
        (b['timestamp'] ?? '').toString(),
      ),
    );
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

  // ========== SALES HISTORY CACHING ==========

  Future<void> cacheSalesHistory(List<Map<String, dynamic>> sales) async {
    await _ensureInitialized();
    await _salesBox.clear();
    for (final sale in sales) {
      final id = sale['id'] as String;
      _salesBox.put(id, sale);
    }
    await _salesBox.flush();
    Logger.info('Cached ${sales.length} sales');
  }

  List<Map<String, dynamic>> getCachedSalesHistory() {
    if (!_initialized) return [];
    final sales = _salesBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    sales.sort(
      (a, b) => (b['created_at'] ?? '').toString().compareTo(
        (a['created_at'] ?? '').toString(),
      ),
    );
    return sales;
  }

  // ========== OFFLINE SALES (pending new sales) ==========

  Future<void> saveSaleOffline(Map<String, dynamic> saleData) async {
    await _ensureInitialized();
    final id =
        saleData['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
    saleData['id'] = id;
    saleData['retry_count'] = 0;
    saleData['last_error'] = null;
    await _pendingBox.put(id, saleData);
    // Also add to local sales cache so it appears in history immediately
    await _salesBox.put(id, saleData);
    Logger.info('Sale saved offline: $id');
  }

  List<Map<String, dynamic>> getPendingSales() {
    if (!_initialized) return [];
    return _pendingBox.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> clearAllPending() async {
    await _ensureInitialized();
    final salesCount = _pendingBox.length;
    final opsCount = _pendingOpsBox.length;
    final writesCount = _pendingWritesBox.length;
    await _pendingBox.clear();
    await _pendingOpsBox.clear();
    await _pendingWritesBox.clear();
    lastSyncError = null;
    print('[SYNC] Cleared $salesCount pending sales, $opsCount pending ops, $writesCount pending writes');
  }

  Future<void> removePendingSale(String id) async {
    await _ensureInitialized();
    await _pendingBox.delete(id);
  }

  // ========== PENDING OPERATIONS (edit/delete queue) ==========

  Future<void> addPendingOperation(Map<String, dynamic> op) async {
    await _ensureInitialized();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    op['id'] = id;
    op['timestamp'] = DateTime.now().toIso8601String();
    op['retry_count'] = 0;
    op['last_error'] = null;
    await _pendingOpsBox.put(id, op);
    Logger.info('Queued operation: ${op['type']} for ${op['sale_id']}');
  }

  List<Map<String, dynamic>> getPendingOperations() {
    if (!_initialized) return [];
    final ops = _pendingOpsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    ops.sort(
      (a, b) => (a['timestamp'] ?? '').toString().compareTo(
        (b['timestamp'] ?? '').toString(),
      ),
    );
    return ops;
  }

  Future<void> removePendingOperation(String id) async {
    await _ensureInitialized();
    await _pendingOpsBox.delete(id);
  }

  // Apply a pending edit to the local sales cache
  void applyEditToLocalCache(String saleId, Map<String, dynamic> updatedSale) {
    if (!_initialized) return;
    _salesBox.put(saleId, updatedSale);
    Logger.info('Updated local cache for sale: $saleId');
  }

  // Apply a pending delete to the local sales cache
  void applyDeleteToLocalCache(String saleId) {
    if (!_initialized) return;
    _salesBox.delete(saleId);
    Logger.info('Removed sale from local cache: $saleId');
  }

  // ========== SYNC ==========

  String? lastSyncError;
  bool _isSyncing = false;

  Future<bool> syncPendingSales() async {
    await _ensureInitialized();
    if (_isSyncing) {
      print('[SYNC] Already syncing, skipping');
      return false;
    }
    _isSyncing = true;

    try {
      return await _syncPendingSalesInner();
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _syncPendingSalesInner() async {
    final sales = getPendingSales();
    final ops = getPendingOperations();
    final writes = getPendingWrites();
    if (sales.isEmpty && ops.isEmpty && writes.isEmpty) {
      lastSyncError = null;
      return true;
    }

    print('[SYNC] Starting sync: ${sales.length} sales, ${ops.length} ops, ${writes.length} writes');
    bool allSynced = true;
    final supabase = Supabase.instance.client;
    lastSyncError = null;

    // Sync pending writes in PARALLEL (purchases, expenses, products, etc.)
    if (writes.isNotEmpty) {
      const maxRetries = 5;
      final writeFutures = <Future>[];
      for (final write in writes) {
        writeFutures.add(
          _syncSingleWrite(write)
              .then((_) async {
                // Remove offline-cached purchase after successful sync
                if (write['table'] == 'purchases' && write['operation'] == 'insert') {
                  final dataId = (write['data'] as Map<String, dynamic>)['id'] as String?;
                  if (dataId != null) {
                    await removeCachedPurchase(dataId);
                  }
                }
                await removePendingWrite(write['id'] as String);
              })
              .catchError((e) async {
                Logger.error('Failed to sync write: ${write['id']}', e);
                final retryCount = (write['retry_count'] as int? ?? 0) + 1;
                write['retry_count'] = retryCount;
                write['last_error'] = e.toString().substring(0, 200.clamp(0, e.toString().length));
                if (retryCount >= maxRetries) {
                  Logger.error('Max retries ($maxRetries) exceeded for write ${write["id"]}, removing', e);
                  await removePendingWrite(write['id'] as String);
                } else {
                  await _pendingWritesBox.put(write['id'] as String, write);
                }
                allSynced = false;
              }),
        );
      }
      await Future.wait(writeFutures);
    }

    // Sync pending operations (edit/delete) in PARALLEL
    if (ops.isNotEmpty) {
      const maxRetries = 5;
      final opFutures = <Future>[];
      for (final op in ops) {
        opFutures.add(
          () async {
            final type = op['type'] as String;
            final saleId = op['sale_id'] as String;

            if (type == 'delete') {
              await supabase.from('sales').delete().eq('id', saleId);
              Logger.info('Synced delete: $saleId');
            } else if (type == 'edit') {
              final data = op['data'] as Map<String, dynamic>;
              final opTimestamp = op['timestamp'] as String?;

              // Check if server version is newer (conflict detection)
              if (opTimestamp != null) {
                final serverSale = await supabase
                    .from('sales')
                    .select('updated_at')
                    .eq('id', saleId)
                    .maybeSingle();

                if (serverSale != null) {
                  final serverUpdated = serverSale['updated_at'] as String?;
                  if (serverUpdated != null && serverUpdated.compareTo(opTimestamp) > 0) {
                    Logger.warning('Conflict detected for sale $saleId — server version is newer, using server version');
                    await removePendingOperation(op['id'] as String);
                    return; // Skip this edit, server version wins
                  }
                }
              }

              await supabase.from('sales').update(data).eq('id', saleId);
              Logger.info('Synced edit: $saleId');
            }

            await removePendingOperation(op['id'] as String);
          }().catchError((e) async {
            Logger.error('Failed to sync operation: ${op['id']}', e);
            final retryCount = (op['retry_count'] as int? ?? 0) + 1;
            op['retry_count'] = retryCount;
            op['last_error'] = e.toString().substring(0, 200.clamp(0, e.toString().length));
            if (retryCount >= maxRetries) {
              Logger.error('Max retries exceeded for operation ${op["id"]}, removing');
              await removePendingOperation(op['id'] as String);
            } else {
              await _pendingOpsBox.put(op['id'] as String, op);
            }
            allSynced = false;
          }),
        );
      }
      await Future.wait(opFutures);
    }

    // Sync new sales in PARALLEL (account entries created per-sale)
    if (sales.isNotEmpty) {
      const maxRetries = 5;
      final saleFutures = <Future>[];
      for (final sale in sales) {
        saleFutures.add(
          () async {
            final saleId = sale['id'] as String;
            print('[SYNC] Attempting sale: $saleId');

            // Duplicate check: only check if saleId is a valid UUID
            // (offline saves use timestamp IDs like "1788097623037" which crash
            // the UUID column comparison with 22P02)
            final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
            if (uuidPattern.hasMatch(saleId)) {
              final existing = await supabase
                  .from('sales')
                  .select('id')
                  .eq('id', saleId)
                  .maybeSingle();
              if (existing != null) {
                print('[SYNC] Sale $saleId already exists — removing from pending');
                await removePendingSale(saleId);
                return;
              }
            }

            final insertData = Map<String, dynamic>.from(sale);
            insertData.remove('id');

            // Remove null/empty/invalid values for UUID fields to avoid FK + 22P02 errors
            for (final key in ['created_by', 'customer_id', 'shop_id']) {
              final val = insertData[key];
              if (val == null || val == '' || val == 'null') {
                insertData.remove(key);
              } else if (val is String && !uuidPattern.hasMatch(val)) {
                insertData.remove(key);
              }
            }

            // Remove non-DB fields that aren't columns
            for (final key in ['due_date', 'updated_at']) {
              final val = insertData[key];
              if (val == null || val == '' || val == 'null') {
                insertData.remove(key);
              }
            }

            // Ensure created_at is present (DB needs it for proper ordering)
            if (insertData['created_at'] == null || insertData['created_at'] == '') {
              insertData['created_at'] = DateTime.now().toUtc().toIso8601String();
            }

            // Ensure numeric fields are actually numbers
            for (final key in ['extra_charges', 'round_off', 'igst_amount', 'cgst_amount', 'sgst_amount', 'cash_amount', 'digital_amount', 'amount_paid', 'due_amount', 'total_amount', 'discount', 'total_discount', 'final_amount']) {
              final val = insertData[key];
              if (val is String) {
                insertData[key] = double.tryParse(val) ?? 0;
              }
            }

            // Sanitize items array: ensure product_ids are valid UUIDs
            if (insertData['items'] is List) {
              final items = (insertData['items'] as List).where((item) {
                if (item is Map) {
                  final pid = item['product_id']?.toString() ?? '';
                  return pid.isNotEmpty && uuidPattern.hasMatch(pid);
                }
                return false;
              }).toList();
              insertData['items'] = items;
            }

            print('[SYNC] Inserting sale $saleId with ${insertData.keys.length} fields: ${insertData.keys.join(', ')}');
            print('[SYNC] Data preview: ${insertData.entries.map((e) => '${e.key}=${e.value.runtimeType}:${e.value}').join(', ')}');

            final inserted = await supabase
                .from('sales')
                .insert(insertData)
                .select()
                .single();

            print('[SYNC] Sale $saleId inserted, creating account entries...');
            try {
              await _createAccountEntries(sale, inserted['id'] as String);
            } catch (ae) {
              print('[SYNC WARNING] Account entries failed for $saleId, but sale is in Supabase: $ae');
            }
            await removePendingSale(saleId);
            // Also remove from local cache (the sale now exists in Supabase with its real UUID)
            await _salesBox.delete(saleId);
            print('[SYNC] Sale $saleId synced successfully');
          }().catchError((e) async {
            final msg = 'Failed to sync sale ${sale['id']}: $e';
            print('[SYNC ERROR] $msg');
            Logger.error(msg);
            lastSyncError = msg;
            final retryCount = (sale['retry_count'] as int? ?? 0) + 1;
            sale['retry_count'] = retryCount;
            sale['last_error'] = e.toString().substring(0, 200.clamp(0, e.toString().length));
            if (retryCount >= maxRetries) {
              Logger.error('Max retries exceeded for sale ${sale["id"]}, removing');
              await removePendingSale(sale['id'] as String);
            } else {
              await _pendingBox.put(sale['id'] as String, sale);
            }
            allSynced = false;
          }),
        );
      }
      await Future.wait(saleFutures);
    }

    // Refresh caches after sync
    if (allSynced) {
      try {
        final response = await supabase
            .from('sales')
            .select()
            .order('created_at', ascending: false)
            .limit(100);
        await cacheSalesHistory(
          List<Map<String, dynamic>>.from(response as List),
        );
      } catch (e) {
        Logger.warning('Failed to refresh sales cache after sync');
      }
    }

    return allSynced;
  }

  Future<void> _syncSingleWrite(Map<String, dynamic> write) async {
    final supabase = Supabase.instance.client;
    final table = write['table'] as String;
    final operation = write['operation'] as String;
    final data = write['data'] as Map<String, dynamic>;

    switch (operation) {
      case 'insert':
        final insertData = Map<String, dynamic>.from(data);
        insertData.remove('id');
        // Check for duplicate before insert (only for valid UUIDs to avoid postgres crash)
        final uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
        if (data['id'] != null && uuidPattern.hasMatch(data['id'] as String)) {
          final existing = await supabase
              .from(table)
              .select('id')
              .eq('id', data['id'] as String)
              .maybeSingle();
          if (existing != null) {
            Logger.warning('Record ${data['id']} already exists in $table — skipping duplicate');
            return;
          }
        }
        await supabase.from(table).insert(insertData);
        Logger.info('Synced insert to $table: ${data['id']}');
        break;
      case 'update':
        final id = data['id'] as String;
        final updateData = Map<String, dynamic>.from(data);
        updateData.remove('id');
        await supabase.from(table).update(updateData).eq('id', id);
        Logger.info('Synced update to $table: $id');
        break;
      case 'delete':
        final id = data['id'] as String;
        await supabase.from(table).delete().eq('id', id);
        Logger.info('Synced delete from $table: $id');
        break;
      case 'stock_add':
        await supabase.rpc(
          'increment_stock',
          params: {'p_product_id': data['product_id'], 'p_qty': data['qty']},
        );
        Logger.info('Synced stock add: ${data['product_id']} +${data['qty']}');
        break;
      case 'stock_deduct':
        await supabase.rpc(
          'decrement_stock',
          params: {'p_product_id': data['product_id'], 'p_qty': data['qty']},
        );
        Logger.info(
          'Synced stock deduct: ${data['product_id']} -${data['qty']}',
        );
        break;
    }
  }

  Future<void> _createAccountEntries(
    Map<String, dynamic> sale,
    String saleId,
  ) async {
    try {
      final isCredit = sale['is_credit'] as bool? ?? false;
      if (isCredit) return;

      final paymentMethod = sale['payment_method'] as String? ?? 'cash';
      final finalAmount = (sale['final_amount'] as num?)?.toDouble() ?? 0;
      final cashAmount = (sale['cash_amount'] as num?)?.toDouble() ?? 0;
      final digitalAmount = (sale['digital_amount'] as num?)?.toDouble() ?? 0;
      if (finalAmount <= 0) return;

      final accountService = AccountService();
      var accounts = await accountService.getAccounts();
      if (accounts.isEmpty) {
        await accountService.ensureAccountsExist();
        accounts = await accountService.getAccounts();
      }
      if (accounts.isEmpty) return;

      final shortId = saleId.length >= 8 ? saleId.substring(0, 8) : saleId;

      if (cashAmount > 0 && digitalAmount > 0) {
        final cashAccount = accounts.firstWhere(
          (a) => a.accountType == 'cash',
          orElse: () => accounts.first,
        );
        await accountService.addTransaction(
          accountId: cashAccount.id,
          type: 'in',
          amount: cashAmount,
          category: 'sale',
          description: 'Sale #$shortId (Cash)',
        );

        final bankAccount = accounts.firstWhere(
          (a) => a.accountType == 'bank',
          orElse: () => accounts.last,
        );
        await accountService.addTransaction(
          accountId: bankAccount.id,
          type: 'in',
          amount: digitalAmount,
          category: 'sale',
          description: 'Sale #$shortId (UPI)',
        );
      } else {
        final accountType =
            (paymentMethod == 'upi' || paymentMethod == 'digital')
            ? 'bank'
            : 'cash';
        final account = accounts.firstWhere(
          (a) => a.accountType == accountType,
          orElse: () => accounts.first,
        );
        await accountService.addTransaction(
          accountId: account.id,
          type: 'in',
          amount: finalAmount,
          category: 'sale',
          description: 'Sale #$shortId',
        );
      }
      Logger.info('Account entry created for synced sale: $saleId');
    } catch (e) {
      Logger.warning('Failed to create account entry for synced sale: $e');
    }
  }

  Future<bool> isOnline() async {
    try {
      // First check basic connectivity
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      final hasConnectivity = results.any((r) => r != ConnectivityResult.none);
      if (!hasConnectivity) return false;

      // Then verify Supabase is actually reachable
      try {
        await Supabase.instance.client
            .from('products')
            .select('id')
            .limit(1)
            .timeout(const Duration(seconds: 5));
        return true;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> forceSync() async {
    print('[SYNC] Force sync requested');
    final result = await syncPendingSales();
    // Also sync queued audit logs
    try {
      final auditService = AuditService();
      await auditService.syncPendingAuditLogs();
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
    return _heldBillsBox.values.toList().cast<Map<String, dynamic>>();
  }

  Future<void> clearHeldBills() async {
    await _ensureInitialized();
    await _heldBillsBox.clear();
  }
}
