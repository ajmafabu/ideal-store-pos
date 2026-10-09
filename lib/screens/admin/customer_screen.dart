import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/customer.dart';
import '../../config/providers.dart';
import '../../services/statement_pdf_generator.dart';
import '../../widgets/empty_state.dart';
import '../../utils/error_messages.dart';
import '../../utils/validators.dart';
import 'debt_detail_screen.dart';
import '../../utils/readable_color.dart';

class CustomerScreen extends ConsumerStatefulWidget {
  const CustomerScreen({super.key});

  @override
  ConsumerState<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends ConsumerState<CustomerScreen> {
  List<Customer> _customers = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _loading = true);
    try {
      final customers = await ref.read(customerServiceProvider).getCustomers();
      if (mounted) {
        setState(() {
          _customers = customers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Customer> get _filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    return _customers
        .where((c) =>
            c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (c.phone?.contains(_searchQuery) ?? false))
        .toList();
  }

  Future<void> _addOrEditCustomer({Customer? existing}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final addressController = TextEditingController(text: existing?.address ?? '');
    final gstinController = TextEditingController(text: existing?.gstin ?? '');
    final stateController = TextEditingController(text: existing?.stateCode ?? '');
    final limitController = TextEditingController(
      text: (existing?.creditLimit ?? 0) > 0 ? existing!.creditLimit.toStringAsFixed(0) : '',
    );

    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing != null ? 'Edit Customer' : 'Add Customer'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) => Validators.required(v, 'Name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: gstinController,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN (business customers)',
                    helperText: 'Needed for B2B invoices in GSTR-1',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: Validators.gstin,
                  onChanged: (v) {
                    final st = Validators.stateFromGstin(v);
                    if (st != null) stateController.text = st;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: stateController,
                  decoration: const InputDecoration(
                    labelText: 'State code',
                    helperText: '33 = Tamil Nadu. Another state means IGST.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    return RegExp(r'^[0-9]{2}$').hasMatch(t) ? null : 'Two digits, e.g. 33';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: limitController,
                  decoration: const InputDecoration(
                    labelText: 'Credit limit (Rs)',
                    helperText: 'Leave empty for no limit',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => Validators.amount(v, required: false, allowZero: true, label: 'Credit limit'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final service = ref.read(customerServiceProvider);
              final gstin = opt(gstinController)?.toUpperCase();
              final limit = double.tryParse(limitController.text.trim());
              try {
                if (existing != null) {
                  await service.updateCustomer(
                    id: existing.id,
                    name: nameController.text.trim(),
                    phone: opt(phoneController),
                    address: opt(addressController),
                    gstin: gstin,
                    stateCode: opt(stateController),
                    creditLimit: limit ?? 0,
                  );
                } else {
                  await service.addCustomer(
                    name: nameController.text.trim(),
                    phone: opt(phoneController),
                    address: opt(addressController),
                    gstin: gstin,
                    stateCode: opt(stateController),
                    creditLimit: limit,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(ErrorMessages.parse(e))),
                  );
                }
              }
            },
            child: Text(existing != null ? 'Update' : 'Add'),
          ),
        ],
      ),
    );

    if (result == true) _loadCustomers();
  }

  Future<void> _exportBalancePdf() async {
    try {
      await StatementPdfGenerator.generateCustomerBalanceList(
        customers: _customers,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${ErrorMessages.parse(e)}')),
        );
      }
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Delete "${customer.name}"?\n\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFC62828))),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await ref.read(customerServiceProvider).deleteCustomer(customer.id);
        _loadCustomers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMessages.parse(e))),
          );
        }
      }
    }
  }

  /// Shares the customer's statement (balance + every bill and payment) as
  /// a PDF. The old "portal link" pointed at a website that does not exist.
  Future<void> _sharePortalLink(Customer customer) async {
    try {
      final service = ref.read(customerServiceProvider);
      final sales = await service.getSalesByCustomer(customer.id);
      final payments = await service.getPaymentsByCustomer(customer.id);
      await StatementPdfGenerator.generateCustomerStatement(
        customer: customer,
        sales: sales,
        payments: payments,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.parse(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportBalancePdf,
            tooltip: 'Export All Balances PDF',
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _addOrEditCustomer(),
            tooltip: 'Add Customer',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustomers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or phone...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // Customer List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                    ? EmptyState(
                        icon: Icons.people_outline,
                        title: 'No Customers',
                        subtitle: 'Add your first customer',
                        actionLabel: 'Add Customer',
                        onAction: () => _addOrEditCustomer(),
                      )
                      : RefreshIndicator(
                        onRefresh: _loadCustomers,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: _filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final customer = _filteredCustomers[index];
                            final hasDebt = customer.totalCredit > 0;
                            final color = hasDebt ? const Color(0xFFFF9800) : const Color(0xFF11998e);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                    style: TextStyle(color: readableText(color), fontWeight: FontWeight.bold, fontSize: 18),
                                  ),
                                ),
                                title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (customer.phone != null)
                                      Text('Phone: ${customer.phone}'),
                                    if (customer.address != null && customer.address!.isNotEmpty)
                                      Text('Address: ${customer.address}'),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (hasDebt)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFeb3349).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'Due: Rs ${customer.totalCredit.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            color: Color(0xFFeb3349),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF11998e).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'No dues',
                                          style: TextStyle(color: Color(0xFF0F766E), fontSize: 12),
                                        ),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.share, size: 20, color: Color(0xFF667eea)),
                                          tooltip: 'Share Statement',
                                          onPressed: () => _sharePortalLink(customer),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 20),
                                          onPressed: () => _addOrEditCustomer(existing: customer),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                          onPressed: () => _deleteCustomer(customer),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DebtDetailScreen(customer: customer),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
