import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

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
  /// Queue items that failed 5 times: kept for review instead of deleted (#6).
  static const String deadLetterBox = 'dead_letters';
  /// The signed-in user's profile, so the app opens offline after a restart.
  static const String cachedProfileBox = 'cached_profile';

  static HiveAesCipher? _currentCipher;

  static HiveAesCipher get cipher {
    if (_currentCipher == null) {
      throw StateError(
        'HiveAdapter.init() must be called before accessing cipher. '
        'Call HiveAdapter.init() in main() before any Hive operations.',
      );
    }
    return _currentCipher!;
  }

  /// Tests only: use an in-memory key instead of the device key file.
  @visibleForTesting
  static void useCipherForTests(HiveAesCipher cipher) => _currentCipher = cipher;

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

  /// Boxes that lost unreadable entries when opened (damaged file or a
  /// changed key). The file as it was is kept in [recoveryDir]; main() tells
  /// the user.
  static final List<String> recoveredBoxes = [];
  static String? recoveryDir;

  /// Opens an encrypted box without silently losing data such as unsent bills.
  ///
  /// Hive repairs a damaged box by cutting it at the first unreadable entry
  /// (with a wrong key: all of it) and raises no error. So the file is copied
  /// first; if opening made it shorter, the copy is kept in
  /// `hive_recovery/<time>/` and the box is reported. A box that cannot be
  /// opened at all (e.g. the app is already running) is never deleted: the
  /// error goes to main(), which tells the user.
  @visibleForTesting
  static Future<Box<Map>> openBoxSafely(String name, HiveAesCipher cipher, String dir) async {
    final sep = Platform.pathSeparator;
    final file = File('$dir$sep$name.hive');
    final sizeBefore = await file.exists() ? await file.length() : 0;
    File? copy;
    if (sizeBefore > 0) {
      try {
        copy = await file.copy('$dir$sep$name.hive.before_open');
      } catch (e) {
        Logger.warning('Could not copy $name before opening: $e');
      }
    }
    try {
      // without a copy, fail loudly instead of cutting the file
      final box = await Hive.openBox<Map>(name, encryptionCipher: cipher, crashRecovery: copy != null);
      final kept = copy;
      if (kept != null && await file.length() < sizeBefore) {
        copy = null;   // keep it
        recoveredBoxes.add(name);
        final now = DateTime.now();
        String two(int n) => n.toString().padLeft(2, '0');
        final folder = Directory('$dir${sep}hive_recovery$sep'
            '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}');
        var keptPath = kept.path;
        try {
          await folder.create(recursive: true);
          keptPath = (await kept.rename('${folder.path}$sep$name.hive')).path;
          recoveryDir = folder.path;
        } catch (e) {
          recoveryDir = dir;   // copy stays next to the box as <name>.hive.before_open
        }
        Logger.error('Local data "$name" was damaged; the original file is kept at $keptPath');
      }
      return box;
    } finally {
      try {
        await copy?.delete();
      } catch (_) {}
    }
  }

  static Future<void> init() async {
    _currentCipher = HiveAesCipher(await _getOrCreateKey());
    final cipher = _currentCipher!;
    final dir = (await getApplicationDocumentsDirectory()).path;   // same folder as Hive.initFlutter()

    Future<Box<Map>> openEncryptedBox(String name) => openBoxSafely(name, cipher, dir);

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
    await openEncryptedBox(deadLetterBox);   // OfflineService reuses the open box
    await openEncryptedBox(cachedProfileBox);   // AuthService reads it by name
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
