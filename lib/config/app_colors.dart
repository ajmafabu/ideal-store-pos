import 'package:flutter/material.dart';

class AppColors {
  // Primary gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient salesGradient = LinearGradient(
    colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient expenseGradient = LinearGradient(
    colors: [Color(0xFFeb3349), Color(0xFFf45c43)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient stockGradient = LinearGradient(
    colors: [Color(0xFF2193b0), Color(0x006dd5fa)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient profitGradient = LinearGradient(
    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient loginGradient = LinearGradient(
    colors: [Color(0xFF667eea), Color(0xFF764ba2), Color(0xFFf093fb)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient fabGradient = LinearGradient(
    colors: [Color(0xFFf093fb), Color(0xFFf5576c)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient appBarGradient = LinearGradient(
    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Category colors
  static const Map<String, Color> categoryColors = {
    'Electronics': Color(0xFF2196F3),
    'Grocery': Color(0xFF4CAF50),
    'Clothing': Color(0xFFE91E63),
    'Pharmacy': Color(0xFFF44336),
    'Food': Color(0xFFFF9800),
    'Beverages': Color(0xFF9C27B0),
    'Snacks': Color(0xFF00BCD4),
    'Home': Color(0xFF795548),
    'Beauty': Color(0xFFFF5722),
    'Sports': Color(0xFF607D8B),
  };

  static Color getCategoryColor(String? category) {
    if (category == null) return Colors.grey;
    return categoryColors[category] ??
        Colors.primaries[category.hashCode % Colors.primaries.length];
  }

  // Payment method colors
  static const Color cashColor = Color(0xFF4CAF50);
  static const Color digitalColor = Color(0xFF2196F3);
  static const Color creditColor = Color(0xFFFF9800);

  static Color getPaymentColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return cashColor;
      case 'digital':
        return digitalColor;
      case 'credit':
        return creditColor;
      case 'split':
        return const Color(0xFF9C27B0);
      default:
        return Colors.grey;
    }
  }

  // Stat card colors
  static const Color todaySalesColor = Color(0xFF11998e);
  static const Color yesterdayColor = Color(0xFF2193b0);
  static const Color todayExpenseColor = Color(0xFFeb3349);
  static const Color stockValueColor = Color(0xFF8E2DE2);
}
