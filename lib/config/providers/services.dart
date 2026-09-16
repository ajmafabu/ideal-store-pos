import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/product_service.dart';
import '../../services/sale_service.dart';
import '../../services/purchase_service.dart';
import '../../services/expense_service.dart';
import '../../services/customer_service.dart';
import '../../services/supplier_service.dart';
import '../../services/account_service.dart';
import '../../services/return_service.dart';
import '../../services/damaged_service.dart';
import '../../services/purchase_order_service.dart';
import '../../services/offline_service.dart';
import '../../services/connectivity_service.dart';

// ============================================
// SERVICE PROVIDERS (DI chain)
// ============================================

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(),
);
final offlineServiceProvider = Provider<OfflineService>(
  (ref) => OfflineService(),
);
final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(),
);

final productServiceProvider = Provider<ProductService>(
  (ref) => ProductService(offlineService: ref.watch(offlineServiceProvider)),
);

final saleServiceProvider = Provider<SaleService>(
  (ref) => SaleService(
    accountService: ref.watch(accountServiceProvider),
    offlineService: ref.watch(offlineServiceProvider),
  ),
);
final purchaseServiceProvider = Provider<PurchaseService>(
  (ref) => PurchaseService(accountService: ref.watch(accountServiceProvider)),
);
final expenseServiceProvider = Provider<ExpenseService>(
  (ref) => ExpenseService(accountService: ref.watch(accountServiceProvider)),
);
final customerServiceProvider = Provider<CustomerService>(
  (ref) => CustomerService(accountService: ref.watch(accountServiceProvider)),
);
final supplierServiceProvider = Provider<SupplierService>(
  (ref) => SupplierService(accountService: ref.watch(accountServiceProvider)),
);
final returnServiceProvider = Provider<ReturnService>(
  (ref) => ReturnService(accountService: ref.watch(accountServiceProvider)),
);
final damagedServiceProvider = Provider<DamagedService>(
  (ref) => DamagedService(),
);
final purchaseOrderServiceProvider = Provider<PurchaseOrderService>(
  (ref) => PurchaseOrderService(),
);
