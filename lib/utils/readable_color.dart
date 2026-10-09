import 'package:flutter/painting.dart';

/// Darker versions of the app's light accent colours, for TEXT on white or
/// light cards. The light shades stay for backgrounds, bars and icons.
///
/// QA test 8 Oct 2026, finding 69: green/orange/grey text measured 2.2–3.3 : 1
/// against white; the readable minimum is 4.5 : 1. Every colour here is ≥ 4.5.
const Map<int, int> _darker = {
  // Material
  0xFF4CAF50: 0xFF2E7D32, // green → green 800
  0xFF66BB6A: 0xFF2E7D32,
  0xFF43A047: 0xFF2E7D32,
  0xFF388E3C: 0xFF2E7D32,
  0xFFF44336: 0xFFC62828, // red → red 800
  0xFFEF5350: 0xFFC62828,
  0xFFE53935: 0xFFC62828,
  0xFFFF5252: 0xFFC62828, // redAccent
  0xFFFF9800: 0xFFC2410C, // orange → burnt orange
  0xFFFFA726: 0xFFC2410C,
  0xFFFB8C00: 0xFFC2410C,
  0xFFF57C00: 0xFFC2410C,
  0xFFEF6C00: 0xFFC2410C,
  0xFFE65100: 0xFFC2410C,
  0xFFFFC107: 0xFFB45309, // amber
  0xFFFF5722: 0xFFC2410C, // deepOrange
  0xFF2196F3: 0xFF1565C0, // blue → blue 800
  0xFF42A5F5: 0xFF1565C0,
  0xFF1E88E5: 0xFF1565C0,
  0xFF1976D2: 0xFF1565C0,
  0xFF9E9E9E: 0xFF757575, // grey / grey 500 → grey 600
  0xFFBDBDBD: 0xFF757575, // grey 400
  0xFF009688: 0xFF00695C, // teal
  0xFF00BCD4: 0xFF00838F, // cyan
  0xFFE91E63: 0xFFC2185B, // pink
  0xFF607D8B: 0xFF455A64, // blueGrey
  // the app's own palette (Tailwind 500s → 700s)
  0xFF10B981: 0xFF047857,
  0xFF059669: 0xFF047857,
  0xFF22C55E: 0xFF15803D,
  0xFFEF4444: 0xFFB91C1C,
  0xFFF59E0B: 0xFFB45309,
  0xFFF97316: 0xFFC2410C,
  0xFF3B82F6: 0xFF1D4ED8,
  0xFF6366F1: 0xFF4338CA,
  0xFF8B5CF6: 0xFF6D28D9,
  0xFF94A3B8: 0xFF64748B,
  0xFFCBD5E1: 0xFF64748B, // slate 300 (1.5 : 1)
  0xFF0EA5E9: 0xFF0369A1,
  0xFFEC4899: 0xFFBE185D,
  0xFF11998E: 0xFF0F766E,
  0xFF667EEA: 0xFF4C51BF,
};

/// A readable text colour for [c]: its darker shade when [c] is one of the
/// light accents above, otherwise [c] unchanged (white, black, theme colours).
Color readableText(Color c) {
  final dark = _darker[c.toARGB32()];
  return dark == null ? c : Color(dark);
}
