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
      height: 48,
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ProviderScope.containerOf(context).read(currentTabProvider.notifier).state = 0,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 14),
                Icon(Icons.menu, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(width: 14),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: List.generate(sessions.length, (index) {
                final session = sessions[index];
                final isActive = index == notifier.activeSessionIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: GestureDetector(
                    onTap: () {
                      notifier.switchSession(index);
                      onCartIndexChanged(-1);
                      onSearchFocusRequested();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SALE ${index + 1}',
                            style: TextStyle(
                              color: isActive ? const Color(0xFF0F172A) : Colors.white.withValues(alpha: 0.7),
                              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                          if (session.items.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFF0F172A).withValues(alpha: 0.1)
                                    : Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '₹${session.total.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: isActive ? const Color(0xFF0F172A) : Colors.white.withValues(alpha: 0.8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          if (sessions.length > 1) ...[
                            const SizedBox(width: 6),
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
                                  size: 13,
                                  color: Colors.orange.withValues(alpha: 0.8),
                                ),
                              ),
                            if (!isActive && session.items.isNotEmpty)
                              const SizedBox(width: 4),
                            if (sessions.length > 1)
                              GestureDetector(
                                onTap: () {
                                  notifier.closeSession(index);
                                  onCartIndexChanged(-1);
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 13,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          GestureDetector(
            onTap: () {
              notifier.createQuickSale();
              onCartIndexChanged(-1);
              onSearchFocusRequested();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 15, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => DesktopSalesHistoryDialog(onEditSale: onEditSale),
            ),
            icon: const Icon(Icons.history, size: 16, color: Colors.white70),
            label: const Text(
              'SALES HISTORY',
              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
