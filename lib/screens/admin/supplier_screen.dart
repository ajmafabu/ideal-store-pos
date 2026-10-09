import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/supplier.dart';
import '../../config/providers.dart';
import '../../services/statement_pdf_generator.dart';
import '../../widgets/empty_state.dart';
import '../../utils/error_messages.dart';
import '../../utils/validators.dart';
import 'supplier_detail_screen.dart';
import '../../utils/readable_color.dart';

class SupplierScreen extends ConsumerStatefulWidget {
  const SupplierScreen({super.key});

  @override
  ConsumerState<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends ConsumerState<SupplierScreen> {
  List<Supplier> _suppliers = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _loading = true);
    try {
      final suppliers = await ref.read(supplierServiceProvider).getSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Supplier> get _filteredSuppliers {
    if (_searchQuery.isEmpty) return _suppliers;
    return _suppliers
        .where((s) =>
            s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (s.phone?.contains(_searchQuery) ?? false))
        .toList();
  }

  Future<void> _addOrEditSupplier({Supplier? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final addressController = TextEditingController(text: existing?.address ?? '');
    final gstController = TextEditingController(text: existing?.gstNumber ?? '');
    // phone "123" and GSTIN "ABC" were accepted (QA #16)
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing != null ? 'Edit Supplier' : 'Add Supplier'),
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
                validator: _supplierPhone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: gstController,
                decoration: const InputDecoration(labelText: 'GST Number'),
                textCapitalization: TextCapitalization.characters,
                validator: Validators.gstin,
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
              if (formKey.currentState?.validate() ?? false) {
                try {
                  if (existing != null) {
                    await ref.read(supplierServiceProvider).updateSupplier(
                      id: existing.id,
                      name: nameController.text,
                      phone: phoneController.text.isNotEmpty ? phoneController.text : null,
                      address: addressController.text.isNotEmpty ? addressController.text : null,
                      gstNumber: gstController.text.isNotEmpty ? gstController.text.trim().toUpperCase() : null,
                    );
                  } else {
                    await ref.read(supplierServiceProvider).addSupplier(
                      name: nameController.text,
                      phone: phoneController.text.isNotEmpty ? phoneController.text : null,
                      address: addressController.text.isNotEmpty ? addressController.text : null,
                      gstNumber: gstController.text.isNotEmpty ? gstController.text.trim().toUpperCase() : null,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
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

    if (result == true) _loadSuppliers();
  }

  /// Mobile or landline (with STD code): 10–12 digits. Empty is allowed.
  static String? _supplierPhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'[\s\-+]'), '');
    if (digits.isEmpty) return null;
    if (!RegExp(r'^\d{10,12}$').hasMatch(digits)) return 'Enter a 10-digit mobile or a landline with STD code';
    return null;
  }

  Future<void> _exportBalancePdf() async {
    try {
      await StatementPdfGenerator.generateSupplierBalanceList(
        suppliers: _suppliers,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${ErrorMessages.parse(e)}')),
        );
      }
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text('Delete "${supplier.name}"?\n\nThis cannot be undone.'),
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
        await ref.read(supplierServiceProvider).deleteSupplier(supplier.id);
        _loadSuppliers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMessages.parse(e))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportBalancePdf,
            tooltip: 'Export All Balances PDF',
          ),
          IconButton(
            icon: const Icon(Icons.business),
            onPressed: () => _addOrEditSupplier(),
            tooltip: 'Add Supplier',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSuppliers,
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

          // Supplier List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? EmptyState(
                        icon: Icons.business_outlined,
                        title: 'No Suppliers',
                        subtitle: 'Add suppliers to track purchases',
                        actionLabel: 'Add Supplier',
                        onAction: () => _addOrEditSupplier(),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadSuppliers,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: _filteredSuppliers.length,
                          itemBuilder: (context, index) {
                            final supplier = _filteredSuppliers[index];
                            final hasDues = supplier.totalDues > 0;
                            final color = hasDues ? const Color(0xFFFF9800) : const Color(0xFF2193b0);
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
                                    supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                                    style: TextStyle(color: readableText(color), fontWeight: FontWeight.bold, fontSize: 18),
                                  ),
                                ),
                                title: Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (supplier.phone != null)
                                      Text('Phone: ${supplier.phone}'),
                                    if (supplier.gstNumber != null)
                                      Text('GST: ${supplier.gstNumber}'),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (hasDues)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFeb3349).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'Due: Rs ${supplier.totalDues.toStringAsFixed(0)}',
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
                                          icon: const Icon(Icons.edit, size: 20),
                                          onPressed: () => _addOrEditSupplier(existing: supplier),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                          onPressed: () => _deleteSupplier(supplier),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SupplierDetailScreen(supplier: supplier),
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
