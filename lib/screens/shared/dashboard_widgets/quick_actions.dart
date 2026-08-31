import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/providers.dart';

class QuickActions extends ConsumerWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actions = [
      _Action(
        Icons.shopping_cart_rounded,
        'New Sale',
        const Color(0xFF10B981),
        tabIndex: 2,
      ),
      _Action(
        Icons.add_shopping_cart_rounded,
        'Purchase',
        const Color(0xFF6366F1),
        tabIndex: 3,
      ),
      _Action(
        Icons.add_box_rounded,
        'Add Product',
        const Color(0xFFF59E0B),
        tabIndex: 1,
      ),
      _Action(
        Icons.people_rounded,
        'Customers',
        const Color(0xFFEC4899),
        tabIndex: 7,
      ),
      _Action(
        Icons.bar_chart_rounded,
        'Reports',
        const Color(0xFF8B5CF6),
        tabIndex: 5,
      ),
      _Action(
        Icons.qr_code_scanner_rounded,
        'Scan',
        const Color(0xFF14B8A6),
        tabIndex: 2, // Navigate to billing where scanner is available
      ),
      _Action(
        Icons.print_rounded,
        'Printer',
        const Color(0xFF64748B),
        navigateTo: '/printer-setup',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Quick Actions',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: actions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final action = actions[index];
              return _QuickActionItem(
                icon: action.icon,
                label: action.label,
                color: action.color,
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (action.tabIndex != null) {
                    ref
                        .read(currentTabProvider.notifier)
                        .setTab(action.tabIndex!);
                  } else if (action.navigateTo != null && context.mounted) {
                    Navigator.pushNamed(context, action.navigateTo!);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Action {
  final IconData icon;
  final String label;
  final Color color;
  final int? tabIndex;
  final String? message;
  final String? navigateTo;

  const _Action(
    this.icon,
    this.label,
    this.color, {
    this.tabIndex,
    this.message,
    this.navigateTo,
  });
}

class _QuickActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
