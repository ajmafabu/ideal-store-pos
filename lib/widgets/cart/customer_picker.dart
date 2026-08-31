import 'package:flutter/material.dart';
import '../../models/customer.dart';

class CustomerPicker extends StatelessWidget {
  final Customer? selectedCustomer;
  final List<Customer> filteredCustomers;
  final TextEditingController searchController;
  final bool showSearch;
  final VoidCallback onToggleSearch;
  final VoidCallback onClearCustomer;
  final VoidCallback onAddCustomer;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Customer> onSelectCustomer;

  const CustomerPicker({
    super.key,
    this.selectedCustomer,
    required this.filteredCustomers,
    required this.searchController,
    required this.showSearch,
    required this.onToggleSearch,
    required this.onClearCustomer,
    required this.onAddCustomer,
    required this.onSearchChanged,
    required this.onSelectCustomer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.person, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: selectedCustomer != null
                  ? Chip(
                      label: Text('${selectedCustomer!.name} ${selectedCustomer!.phone != null ? "(${selectedCustomer!.phone})" : ""}'),
                      onDeleted: onClearCustomer,
                    )
                  : GestureDetector(
                      onTap: onToggleSearch,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          children: [
                            Text('Select Customer (Optional)', style: TextStyle(color: Colors.grey)),
                            Spacer(),
                            Icon(Icons.arrow_drop_down, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onAddCustomer,
              tooltip: 'Add New Customer',
            ),
          ],
        ),
        if (showSearch && selectedCustomer == null) ...[
          const SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search by name or phone...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: onSearchChanged,
                  ),
                ),
                Expanded(
                  child: filteredCustomers.isEmpty
                      ? const Center(child: Text('No customers found'))
                      : ListView.builder(
                          itemCount: filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final customer = filteredCustomers[index];
                            return ListTile(
                              dense: true,
                              title: Text(customer.name),
                              subtitle: customer.phone != null ? Text(customer.phone!) : null,
                              trailing: customer.totalCredit > 0
                                  ? Text('Due: Rs ${customer.totalCredit.toStringAsFixed(0)}',
                                      style: const TextStyle(color: Colors.red, fontSize: 12))
                                  : null,
                              onTap: () => onSelectCustomer(customer),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
