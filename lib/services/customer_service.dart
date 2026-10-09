import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/payment_methods.dart';
import '../utils/network_errors.dart';
import '../models/sale.dart' show newDocumentId;
import '../models/customer.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import 'account_service.dart';
import 'offline_service.dart';
import '../utils/paged_query.dart';
import '../utils/search_term.dart';

class CustomerService {
  final SupabaseClient _supabase;
  final OfflineService _offlineService;

  CustomerService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _supabase = client ?? Supabase.instance.client,
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
      final response = await _supabase.from('customers').select().order('name', ascending: true);
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

  // Add customer. Server rejections are thrown; only a network failure is
  // queued (it used to queue every error and report success). The id is made
  // here, so a customer added offline can be put on a bill at once and keeps
  // the same id when it syncs (customers sync before the sales that use them).
  Future<Customer> addCustomer({
    required String name,
    String? phone,
    String? address,
    String? gstin,
    String? stateCode,
    double? creditLimit,
  }) async {
    final data = <String, dynamic>{
      'id': newDocumentId(),
      'name': name,
      'phone': phone,
      'address': address,
      'gstin': gstin,
      if (stateCode != null) 'state_code': stateCode,
      if (creditLimit != null) 'credit_limit': creditLimit,
    };
    try {
      final response = await _supabase.from('customers').insert(data).select().single();
      return Customer.fromJson(response);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      Logger.warning('addCustomer offline, queuing: $e');
      await _offlineService.queuePendingWrite({'table': 'customers', 'operation': 'insert', 'data': Map<String, dynamic>.from(data)});
      return Customer.fromJson(data);
    }
  }

  // Update customer
  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? address,
    String? gstin,
    String? stateCode,
    double? creditLimit,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'phone': phone,
      'address': address,
      'gstin': gstin,
      if (stateCode != null) 'state_code': stateCode,
      if (creditLimit != null) 'credit_limit': creditLimit,
    };
    try {
      await _supabase.from('customers').update(data).eq('id', id);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      Logger.warning('updateCustomer offline, queuing: $e');
      await _offlineService.queuePendingWrite({
        'table': 'customers',
        'operation': 'update',
        'data': {'id': id, ...data},
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
      return await fetchAllRows(
        () => _supabase.from('sales').select().eq('customer_id', customerId),
        orderBy: 'created_at',
        ascending: false,
      );
    } catch (e) {
      // thrown, not []: an empty list looked like "no bills" (and made an
      // empty customer statement)
      Logger.error('getSalesByCustomer', e);
      rethrow;
    }
  }

  // Get payments by customer
  Future<List<Map<String, dynamic>>> getPaymentsByCustomer(
    String customerId,
  ) async {
    try {
      return await fetchAllRows(
        () => _supabase.from('payments').select().eq('customer_id', customerId),
        orderBy: 'created_at',
        ascending: false,
      );
    } catch (e) {
      Logger.error('getPaymentsByCustomer', e);
      rethrow;
    }
  }

  /// Records money collected against a credit sale. The database checks it
  /// is not more than the amount due, reduces the sale's due and the
  /// customer's balance, and books it into cash or bank from the payment
  /// method — all in one step (#10, #12). A server rejection is thrown;
  /// only a network failure queues the payment (with a stable id).
  Future<void> recordPayment({
    required String customerId,
    required String saleId,
    required double amount,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    final data = {
      'id': newDocumentId(),
      'customer_id': customerId,
      'sale_id': saleId,
      'amount': amount,
      'payment_method': PaymentMethods.normalize(paymentMethod),
      'notes': notes,
    };
    try {
      await _supabase.from('payments').insert({...data, 'created_by': _supabase.auth.currentUser?.id});
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      Logger.warning('Payment could not reach the server, queuing: $e');
      await _offlineService.queuePendingWrite({'table': 'payments', 'operation': 'insert', 'data': data});
    }
  }

  // Search customers by name or phone
  Future<List<Customer>> searchCustomers(String query) async {
    final q = searchTerm(query);
    final response = await _supabase
        .from('customers')
        .select()
        .or('name.ilike.%$q%,phone.ilike.%$q%')
        .order('name', ascending: true)
        .limit(20);
    return (response as List).map((json) => Customer.fromJson(json)).toList();
  }

  // Get total debt of all customers
  Future<double> getTotalDebt() async {
    final response = await fetchAllRows(() => _supabase.from('customers').select('id, total_credit'));
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
      rethrow;
    }
  }

  // Get overdue payments
  Future<List<Map<String, dynamic>>> getOverduePayments() async {
    try {
      final sales = await fetchAllRows(
        () => _supabase
            .from('sales')
            .select('id, customer_id, final_amount, due_amount, due_date, created_at')
            .eq('is_credit', true)
            .gt('due_amount', 0),
        orderBy: 'due_date',
      );
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
