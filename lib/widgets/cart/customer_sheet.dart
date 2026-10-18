import 'package:flutter/material.dart';

import '../../models/customer.dart';
import 'cart_item_tile.dart' show rupees;

/// The shop's choice in [CustomerSheet]: a customer, or walk-in (null).
class CustomerChoice {
  const CustomerChoice(this.customer);
  final Customer? customer;
}

/// Pick the bill's customer (17 Oct 2026). Before, the customer was inside
/// the small ⚙ button at the bottom, so a credit sale had no visible place
/// to choose one. Search by name or phone; each customer shows what they
/// owe; "Walk-in" clears it; "New customer" adds one.
class CustomerSheet extends StatefulWidget {
  const CustomerSheet({super.key, required this.customers, required this.selected, required this.onAddNew});

  final List<Customer> customers;
  final Customer? selected;

  /// Opens the add-customer form; returns the new customer (or null).
  final Future<Customer?> Function() onAddNew;

  static Future<CustomerChoice?> show(
    BuildContext context, {
    required List<Customer> customers,
    required Customer? selected,
    required Future<Customer?> Function() onAddNew,
  }) {
    return showModalBottomSheet<CustomerChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CustomerSheet(customers: customers, selected: selected, onAddNew: onAddNew),
    );
  }

  @override
  State<CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<CustomerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Customer> get _found {
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? List.of(widget.customers)
        : widget.customers
            .where((c) => c.name.toLowerCase().contains(q) || (c.phone ?? '').contains(q))
            .toList();
    // names that start with what was typed first, then A–Z
    list.sort((a, b) {
      final sa = a.name.toLowerCase().startsWith(q) ? 0 : 1;
      final sb = b.name.toLowerCase().startsWith(q) ? 0 : 1;
      return sa != sb ? sa - sb : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = _found;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final c = await widget.onAddNew();
                      if (c != null && context.mounted) Navigator.pop(context, CustomerChoice(c));
                    },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('New customer'),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Name or phone',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.storefront)),
              title: const Text('Walk-in customer'),
              subtitle: const Text('No name on the bill (no credit)'),
              trailing: widget.selected == null ? Icon(Icons.check_circle, color: scheme.primary) : null,
              onTap: () => Navigator.pop(context, const CustomerChoice(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: found.isEmpty
                  ? Center(
                      child: Text(
                        'No customer "${_search.text.trim()}". Tap New customer to add.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: found.length,
                      itemBuilder: (_, i) {
                        final c = found[i];
                        final owes = c.totalCredit > 0.004;
                        return ListTile(
                          leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: (c.phone ?? '').isEmpty ? null : Text(c.phone!),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (owes)
                                Text(
                                  'Due ${rupees(c.totalCredit)}',
                                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                                ),
                              if (widget.selected?.id == c.id) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.check_circle, color: scheme.primary),
                              ],
                            ],
                          ),
                          onTap: () => Navigator.pop(context, CustomerChoice(c)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
