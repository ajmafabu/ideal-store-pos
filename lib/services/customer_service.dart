import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import 'account_service.dart';
import 'offline_service.dart';

class CustomerService {
  final SupabaseClient _supabase;
  final AccountService? _accountService;
  final OfflineService _offlineService;

  CustomerService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _supabase = client ?? Supabase.instance.client,
       _accountService = accountService,
       _offlineService = offlineService ?? OfflineService();

  // Get all customers
  Future<List<Customer>> getCustomers() async {
    final online = await _offlineService.isOnline();
    if (!online) {
      try {
        final cached = _offlineService.getCachedCustomers();
        if (cached.isNotEmpty) {
          return cached.map((e) => Customer.fromJson(e)).toList();
        }
      } catch (e) {
        Logger.warning('Failed to read cached customers (offline): $e');
      }
      return [];
    }

    try {
      final response = await _supabase.from('customers').select().order('name');
      final customers = (response as List)
          .map((json) => Customer.fromJson(json))
          .toList();

      // Cache customers for offline use
      try {
        await _offlineService.cacheCustomers(
          customers
              .map(
                (c) => {
                  'id': c.id,
                  'name': c.name,
                  'phone': c.phone,
                  'address': c.address,
                  'total_credit': c.totalCredit,
                  'state_code': c.stateCode,
                  'credit_limit': c.creditLimit,
                },
              )
              .toList(),
        );
      } catch (e) {
        Logger.warning('Failed to cache customers: $e');
      }

      return customers;
    } catch (e) {
      Logger.error('getCustomers', e);
      // Try to load from offline cache
      try {
        final cached = _offlineService.getCachedCustomers();
        if (cached.isNotEmpty) {
          return cached.map((e) => Customer.fromJson(e)).toList();
        }
      } catch (e) {
        Logger.warning('Failed to read cached customers (fallback): $e');
      }
      return [];
    }
  }

  // Get customers with due amount
  Future<List<Customer>> getCustomersWithDue() async {
    try {
      final response = await _supabase
          .from('customers')
          .select()
          .gt('total_credit', 0)
          .order('total_credit', ascending: false);
      return (response as List).map((json) => Customer.fromJson(json)).toList();
    } catch (e) {
      Logger.error('getCustomersWithDue', e);
      return [];
    }
  }

  // Add customer
  Future<Customer?> addCustomer({
    required String name,
    String? phone,
    String? address,
  }) async {
    try {
      final response = await _supabase
          .from('customers')
          .insert({'name': name, 'phone': phone, 'address': address})
          .select()
          .single();
      return Customer.fromJson(response);
    } catch (e) {
      Logger.error('addCustomer', e);
      // Queue for offline
      await _offlineService.queuePendingWrite({
        'table': 'customers',
        'operation': 'insert',
        'data': {'name': name, 'phone': phone, 'address': address},
      });
      return null;
    }
  }

  // Update customer
  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? address,
  }) async {
    try {
      await _supabase
          .from('customers')
          .update({'name': name, 'phone': phone, 'address': address})
          .eq('id', id);
    } catch (e) {
      Logger.error('updateCustomer', e);
      await _offlineService.queuePendingWrite({
        'table': 'customers',
        'operation': 'update',
        'data': {'id': id, 'name': name, 'phone': phone, 'address': address},
      });
    }
  }

  // Delete customer
  Future<void> deleteCustomer(String id) async {
    final online = await _offlineService.isOnline();
    if (!online) {
      await _offlineService.queuePendingWrite({
        'table': 'customers',
        'operation': 'delete',
        'data': {'id': id},
      });
      return;
    }

    try {
      await _supabase.from('customers').delete().eq('id', id);
    } catch (e) {
      Logger.error('deleteCustomer', e);
      rethrow;
    }
  }

  // Get sales by customer
  Future<List<Map<String, dynamic>>> getSalesByCustomer(
    String customerId,
  ) async {
    try {
      final response = await _supabase
          .from('sales')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      Logger.error('getSalesByCustomer', e);
      return [];
    }
  }

  // Get payments by customer
  Future<List<Map<String, dynamic>>> getPaymentsByCustomer(
    String customerId,
  ) async {
    try {
      final response = await _supabase
          .from('payments')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      Logger.error('getPaymentsByCustomer', e);
      return [];
    }
  }

  // Record payment
  Future<void> recordPayment({
    required String customerId,
    required String saleId,
    required double amount,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final online = await _offlineService.isOnline();
    if (!online) {
      await _offlineService.queuePendingWrite({
        'table': 'payments',
        'operation': 'insert',
        'data': {
          'customer_id': customerId,
          'sale_id': saleId,
          'amount': amount,
          'payment_method': paymentMethod,
          'notes': notes,
        },
      });
      return;
    }

    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from('payments').insert({
        'customer_id': customerId,
        'sale_id': saleId,
        'amount': amount,
        'payment_method': paymentMethod,
        'notes': notes,
        'created_by': user?.id,
      });

      // Wire to accounts: credit collection = Money In
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
            type: 'in',
            amount: amount,
            category: 'credit_collection',
            description: 'Credit collected from customer',
          );
        } catch (e) {
          Logger.warning('Account entry failed for customer payment: $e');
        }
      }
    } catch (e) {
      Logger.error('recordPayment', e);
      rethrow;
    }
  }

  // Update sale credit fields
  Future<void> updateSaleCredit({
    required String saleId,
    required String? customerId,
    required bool isCredit,
    required double amountPaid,
    required double dueAmount,
  }) async {
    await _supabase
        .from('sales')
        .update({
          'customer_id': customerId,
          'is_credit': isCredit,
          'amount_paid': amountPaid,
          'due_amount': dueAmount,
        })
        .eq('id', saleId);
  }

  // Search customers by name or phone
  Future<List<Customer>> searchCustomers(String query) async {
    final response = await _supabase
        .from('customers')
        .select()
        .or('name.ilike.%$query%,phone.ilike.%$query%')
        .order('name')
        .limit(20);
    return (response as List).map((json) => Customer.fromJson(json)).toList();
  }

  // Get total debt of all customers
  Future<double> getTotalDebt() async {
    final response = await _supabase.from('customers').select('total_credit');
    double total = 0;
    for (final row in response) {
      total += (row['total_credit'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  // Get receivables aging analysis
  Future<List<Map<String, dynamic>>> getReceivablesAging() async {
    try {
      final response = await _supabase.rpc('get_receivables_aging');
      return (response as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      Logger.error('getReceivablesAging', e);
      return [];
    }
  }

  // Get overdue payments
  Future<List<Map<String, dynamic>>> getOverduePayments() async {
    try {
      final response = await _supabase
          .from('sales')
          .select(
            'id, customer_id, final_amount, due_amount, due_date, created_at',
          )
          .eq('is_credit', true)
          .gt('due_amount', 0)
          .order('due_date');
      final sales = (response as List).cast<Map<String, dynamic>>();
      final now = AppTimezone.nowIst();
      return sales.where((s) {
        final dueDate = s['due_date'] != null
            ? DateTime.tryParse(s['due_date'])
            : null;
        return dueDate != null && dueDate.isBefore(now);
      }).toList();
    } catch (e) {
      return [];
    }
  }
}
