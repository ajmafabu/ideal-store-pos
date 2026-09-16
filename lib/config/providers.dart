import 'package:flutter/material.dart';

export 'providers/services.dart';
export 'providers/auth.dart';
export 'providers/products.dart';
export 'providers/sales.dart';
export 'providers/purchases.dart';
export 'providers/expenses.dart';
export 'providers/customers.dart';
export 'providers/dashboard.dart';
export 'providers/accounts.dart';
export 'providers/analytics.dart';
export 'providers/navigation.dart';
export 'providers/realtime.dart';
export 'providers/cart.dart';
export 'providers/returns.dart';
export 'providers/sync.dart';
export 'providers/enhanced_dashboard.dart';

// ============================================
// HELPER WIDGET
// ============================================

// Helper for showing error states in UI
class DataLoadError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const DataLoadError({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
