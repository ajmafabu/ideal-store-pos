import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/customer.dart';
import '../../models/supplier.dart';
import '../../models/profile.dart';
import 'services.dart';

// ============================================
// CUSTOMERS & SUPPLIERS
// ============================================

final customersProvider = FutureProvider<List<Customer>>((ref) async {
  final service = ref.watch(customerServiceProvider);
  return service.getCustomers();
});

final suppliersProvider = FutureProvider<List<Supplier>>((ref) async {
  final service = ref.watch(supplierServiceProvider);
  return service.getSuppliers();
});

// ============================================
// STAFF
// ============================================

final staffListProvider = FutureProvider<List<Profile>>((ref) async {
  try {
    final response = await Supabase.instance.client
        .from('profiles')
        .select()
        .order('name');
    return (response as List).map((e) => Profile.fromJson(e)).toList();
  } catch (e) {
    return [];
  }
});

// ============================================
// ENHANCED DASHBOARD — DUES
// ============================================

final totalCustomerDuesProvider = FutureProvider<double>((ref) async {
  try {
    final customers = await ref.read(customersProvider.future);
    double total = 0;
    for (final c in customers) {
      total += c.totalCredit;
    }
    return total;
  } catch (e) {
    return 0;
  }
});

final totalSupplierDuesProvider = FutureProvider<double>((ref) async {
  try {
    final suppliers = await ref.read(suppliersProvider.future);
    double total = 0;
    for (final s in suppliers) {
      total += s.totalDues;
    }
    return total;
  } catch (e) {
    return 0;
  }
});
