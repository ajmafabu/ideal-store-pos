import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier.dart';
import '../utils/logger.dart';
import 'account_service.dart';
import 'offline_service.dart';

class SupplierService {
  final SupabaseClient _supabase;
  final AccountService? _accountService;
  final OfflineService _offlineService;

  SupplierService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _supabase = client ?? Supabase.instance.client,
       _accountService = accountService,
       _offlineService = offlineService ?? OfflineService();

  Future<List<Supplier>> getSuppliers() async {
    final online = await _offlineService.isOnline();
    if (!online) {
      try {
        final cached = _offlineService.getCachedSuppliers();
        if (cached.isNotEmpty) {
          return cached.map((e) => Supplier.fromJson(e)).toList();
        }
      } catch (e) {
        Logger.warning('Failed to read cached suppliers (offline): $e');
      }
      return [];
    }

    try {
      final response = await _supabase.from('suppliers').select().order('name');
      final list = (response as List)
          .map((json) => Supplier.fromJson(json))
          .toList();
      // Cache for offline
      try {
        await _offlineService.cacheSuppliers(
          list.map((s) => s.toJson()).toList(),
        );
      } catch (e) {
        Logger.warning('Failed to cache suppliers for offline: $e');
      }
      return list;
    } catch (e) {
      Logger.error('getSuppliers', e);
      // Offline fallback
      try {
        final cached = _offlineService.getCachedSuppliers();
        if (cached.isNotEmpty) {
          return cached.map((e) => Supplier.fromJson(e)).toList();
        }
      } catch (e) {
        Logger.warning('Failed to read cached suppliers (fallback): $e');
      }
      return [];
    }
  }

  Future<List<Supplier>> getSuppliersWithDues() async {
    try {
      final response = await _supabase
          .from('suppliers')
          .select()
          .gt('total_dues', 0)
          .order('total_dues', ascending: false);
      return (response as List).map((json) => Supplier.fromJson(json)).toList();
    } catch (e) {
      Logger.error('getSuppliersWithDues', e);
      return [];
    }
  }

  Future<Supplier?> addSupplier({
    required String name,
    String? phone,
    String? address,
    String? gstNumber,
  }) async {
    try {
      final response = await _supabase
          .from('suppliers')
          .insert({
            'name': name,
            'phone': phone,
            'address': address,
            'gst_number': gstNumber,
          })
          .select()
          .single();
      return Supplier.fromJson(response);
    } catch (e) {
      Logger.error('addSupplier', e);
      // Queue for offline
      await _offlineService.queuePendingWrite({
        'table': 'suppliers',
        'operation': 'insert',
        'data': {
          'name': name,
          'phone': phone,
          'address': address,
          'gst_number': gstNumber,
        },
      });
      return null;
    }
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? gstNumber,
  }) async {
    try {
      await _supabase
          .from('suppliers')
          .update({
            'name': name,
            'phone': phone,
            'address': address,
            'gst_number': gstNumber,
          })
          .eq('id', id);
    } catch (e) {
      Logger.error('updateSupplier', e);
      await _offlineService.queuePendingWrite({
        'table': 'suppliers',
        'operation': 'update',
        'data': {
          'id': id,
          'name': name,
          'phone': phone,
          'address': address,
          'gst_number': gstNumber,
        },
      });
    }
  }

  Future<void> deleteSupplier(String id) async {
    try {
      await _supabase.from('suppliers').delete().eq('id', id);
    } catch (e) {
      Logger.error('deleteSupplier', e);
      await _offlineService.queuePendingWrite({
        'table': 'suppliers',
        'operation': 'delete',
        'data': {'id': id},
      });
    }
  }

  Future<List<Map<String, dynamic>>> getPurchasesBySupplier(
    String supplierId,
  ) async {
    try {
      final response = await _supabase
          .from('purchases')
          .select()
          .eq('supplier_id', supplierId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      Logger.error('getPurchasesBySupplier', e);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPaymentsBySupplier(
    String supplierId,
  ) async {
    try {
      final response = await _supabase
          .from('supplier_payments')
          .select()
          .eq('supplier_id', supplierId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      Logger.error('getPaymentsBySupplier', e);
      return [];
    }
  }

  Future<void> recordPayment({
    required String supplierId,
    required String purchaseId,
    required double amount,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from('supplier_payments').insert({
        'supplier_id': supplierId,
        'purchase_id': purchaseId,
        'amount': amount,
        'payment_method': paymentMethod,
        'notes': notes,
        'created_by': user?.id,
      });

      if (_accountService != null) {
        try {
          final accounts = await _accountService!.getAccounts();
          String accountType = paymentMethod == 'upi' ? 'bank' : 'cash';
          final account = accounts.firstWhere(
            (a) => a.accountType == accountType,
            orElse: () => accounts.first,
          );
          await _accountService!.addTransaction(
            accountId: account.id,
            type: 'out',
            amount: amount,
            category: 'credit_payment',
            description: 'Credit payment to supplier',
          );
        } catch (e) {
          Logger.warning(
            'Failed to add account entry for supplier payment: $e',
          );
        }
      }
    } catch (e) {
      Logger.warning('recordPayment failed, queuing offline: $e');
      await _offlineService.queuePendingWrite({
        'table': 'supplier_payments',
        'operation': 'insert',
        'data': {
          'supplier_id': supplierId,
          'purchase_id': purchaseId,
          'amount': amount,
          'payment_method': paymentMethod,
          'notes': notes,
        },
      });
    }
  }

  Future<void> updatePurchaseCredit({
    required String purchaseId,
    required String? supplierId,
    required bool isCredit,
    required double amountPaid,
    required double dueAmount,
  }) async {
    try {
      await _supabase
          .from('purchases')
          .update({
            'supplier_id': supplierId,
            'is_credit': isCredit,
            'amount_paid': amountPaid,
            'due_amount': dueAmount,
          })
          .eq('id', purchaseId);
    } catch (e) {
      Logger.error('updatePurchaseCredit', e);
    }
  }

  Future<List<Supplier>> searchSuppliers(String query) async {
    try {
      final response = await _supabase
          .from('suppliers')
          .select()
          .or('name.ilike.%$query%,phone.ilike.%$query%')
          .order('name')
          .limit(20);
      return (response as List).map((json) => Supplier.fromJson(json)).toList();
    } catch (e) {
      Logger.error('searchSuppliers', e);
      return [];
    }
  }

  Future<double> getTotalDues() async {
    try {
      final response = await _supabase.from('suppliers').select('total_dues');
      double total = 0;
      for (final row in response) {
        total += (row['total_dues'] as num?)?.toDouble() ?? 0;
      }
      return total;
    } catch (e) {
      Logger.error('getTotalDues', e);
      return 0;
    }
  }
}
