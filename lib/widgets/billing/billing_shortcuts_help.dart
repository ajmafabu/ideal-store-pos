import 'package:flutter/material.dart';

class BillingShortcutsHelp extends StatelessWidget {
  const BillingShortcutsHelp({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const BillingShortcutsHelp(),
    );
  }

  static const _shortcuts = [
    _ShortcutGroup(
      title: 'Navigation',
      items: [
        _Shortcut('Tab', 'Move to next field'),
        _Shortcut('Shift + Tab', 'Move to previous field'),
        _Shortcut('Ctrl + Tab', 'Jump to payment panel'),
        _Shortcut('↑ / ↓', 'Navigate search results or cart items'),
      ],
    ),
    _ShortcutGroup(
      title: 'Search & Entry',
      items: [
        _Shortcut('Enter', 'Select search result / Confirm field / Edit cart item'),
        _Shortcut('Escape', 'Cancel edit / Clear search / Back to search'),
        _Shortcut('F3', 'Toggle SFW / Name search mode'),
      ],
    ),
    _ShortcutGroup(
      title: 'Cart',
      items: [
        _Shortcut('Delete / Backspace', 'Remove selected cart item'),
        _Shortcut('+ / -', 'Increment / Decrement selected item qty'),
        _Shortcut('F2', 'Edit selected cart item'),
        _Shortcut('Ctrl + Delete', 'Clear entire cart'),
      ],
    ),
    _ShortcutGroup(
      title: 'Payment',
      items: [
        _Shortcut('F8', 'Select Cash payment'),
        _Shortcut('F9', 'Select UPI payment'),
        _Shortcut('F10', 'Select Credit payment'),
        _Shortcut('F11', 'Toggle Split payment'),
        _Shortcut('Shift + Enter', 'Complete / Update sale'),
      ],
    ),
    _ShortcutGroup(
      title: 'Pricing',
      items: [
        _Shortcut('F5', 'Cycle pricing tier (Normal → Wholesale → Bulk)'),
      ],
    ),
    _ShortcutGroup(
      title: 'Quick Actions',
      items: [
        _Shortcut('F4', 'Open customer picker'),
        _Shortcut('F6', 'Hold current bill'),
        _Shortcut('F7', 'Retrieve held bill'),
        _Shortcut('F12', 'Open calculator (Windows)'),
        _Shortcut('Ctrl + Shift + N', 'Add new product'),
        _Shortcut('Ctrl + D', 'Add new customer'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.keyboard, size: 20),
          SizedBox(width: 8),
          Text('Keyboard Shortcuts'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final group in _shortcuts) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(
                    group.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF667eea),
                    ),
                  ),
                ),
                _buildShortcutTable(group.items),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildShortcutTable(List<_Shortcut> items) {
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(200),
        1: FlexColumnWidth(),
      },
      children: [
        for (final shortcut in items)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    shortcut.key,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 12,
                ),
                child: Text(
                  shortcut.description,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _ShortcutGroup {
  const _ShortcutGroup({required this.title, required this.items});

  final String title;
  final List<_Shortcut> items;
}

class _Shortcut {
  const _Shortcut(this.key, this.description);

  final String key;
  final String description;
}
