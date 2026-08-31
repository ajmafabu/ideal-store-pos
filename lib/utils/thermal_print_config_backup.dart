/// BACKUP of thermal print settings before sample-receipt layout update.
/// If new layout fails, revert tamil_bitmap_renderer.dart and
/// thermal_invoice.dart to match this configuration.
///
/// Date: 2026-08-22
/// Reason: Matching 80mm sample receipt layout from MKM shop
library;

// ============================================
// OLD TAMIL BITMAP RENDERER SETTINGS
// ============================================

/// Old column layout: 5 columns (S.No, Particulars, Qty, Rate, Amt)
/// Total width: 589px
class OldColumnLayout {
  static const double printableWidthPx = 589;
  static const double dpi = 203;

  // 5-column layout
  static const double snoX = 0;
  static const double snoW = 35;
  static const double partX = 38;
  static const double partW = 262;
  static const double qtyX = 305;
  static const double qtyW = 55;
  static const double rateX = 365;
  static const double rateW = 95;
  static const double amtX = 470;
  static const double amtW = 100;
}

/// Old header rendering:
///   displayName (centered, 28pt bold)
///   'QUOTATION' (centered, 22pt bold)
///   'Date: ...  Time: ...' (centered, 22pt bold)
///   'Customer: ...' (centered, 26pt bold)
///
/// Old table header:
///   S.No (center, 20pt bold)
///   Particulars (left, 20pt bold)
///   Qty (right, 20pt bold)
///   Rate (right, 20pt bold)
///   Amt (right, 20pt bold)
///
/// Old data rows:
///   S.No (center, 26pt bold)
///   Particulars (left, 26pt bold) — truncated at 20 chars
///   Qty (right, 26pt bold)
///   Rate (right, 26pt bold)
///   Amt (right, 26pt bold)
///
/// Old total:
///   'Total Items: N' (centered, 20pt bold)
///   'Discount: ...' (centered, 20pt)
///   'Extra: ...' (centered, 20pt)
///   'Round Off: ...' (centered, 20pt)
///   'NET TOTAL: ...' (right-aligned, 24pt bold)
///
/// Old footer:
///   'thank you' (centered, 20pt)
///
/// Old ThermalInvoice header:
///   [displayName, 'QUOTATION', 'Date: $dateStr  Time: $timeStr', 'Customer: $customerName']
///   footerLines: ['thank you']

/// Old ThermalPrinterService font sizes:
///   Bold lines: 36pt
///   Regular lines: 30pt
