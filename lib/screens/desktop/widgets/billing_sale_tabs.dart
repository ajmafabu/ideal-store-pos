import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/providers.dart';
import '../../../config/desktop_billing_provider.dart';
import '../../../models/sale.dart';
import '../dialogs/sales_history_dialog.dart';

class BillingSaleTabs extends StatelessWidget {
  final List<SaleSession> sessions;
  final DesktopBillingNotifier notifier;
  final int selectedCartIndex;
  final void Function(int) onCartIndexChanged;
  final VoidCallback onSearchFocusRequested;
  final void Function(Sale sale) onEditSale;

  const BillingSaleTabs({
    super.key,
    required this.sessions,
    required this.notifier,
    required this.selectedCartIndex,
    required this.onCartIndexChanged,
    required this.onSearchFocusRequested,
    required this.onEditSale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ProviderScope.containerOf(context).read(currentTabProvider.notifier).state = 0,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 10),
                Icon(Icons.arrow_back, color: Colors.white70, size: 16),
                SizedBox(width: 4),
                Text('Menu', style: TextStyle(color: Colors.white70, fontSize: 11)),
                SizedBox(width: 10),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: List.generate(sessions.length, (index) {
                final session = sessions[index];
                final isActive = index == notifier.activeSessionIndex;
                return GestureDetector(
                  onTap: () {
                    notifier.switchSession(index);
                    onCartIndexChanged(-1);
                    onSearchFocusRequested();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF667eea)
                          : Colors.transparent,
                      border: Border(
                        right: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'SALE ${index + 1}',
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                        if (session.items.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Rs${session.total.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.grey,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                        if (sessions.length > 1) ...[
                          const SizedBox(width: 4),
                          if (!isActive && session.items.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                notifier.mergeIntoActive(index);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Merged SALE ${index + 1} into SALE ${notifier.activeSessionIndex + 1}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.merge_type,
                                size: 14,
                                color: Colors.orange.withValues(alpha: 0.7),
                              ),
                            ),
                          if (!isActive && session.items.isNotEmpty)
                            const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              notifier.closeSession(index);
                              onCartIndexChanged(-1);
                            },
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.grey.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          TextButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => DesktopSalesHistoryDialog(
                onEditSale: onEditSale,
              ),
            ),
            icon: const Icon(Icons.history, size: 16, color: Colors.white),
            label: const Text(
              'SALES HISTORY',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          GestureDetector(
            onTap: () {
              notifier.createQuickSale();
              onCartIndexChanged(-1);
              onSearchFocusRequested();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: const Row(
                children: [
                  Icon(Icons.add, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'NEW',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
