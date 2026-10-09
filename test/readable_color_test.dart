import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/utils/readable_color.dart';

/// QA test 8 Oct 2026, finding 69: faded text. Every text colour the app
/// swaps in must reach the readable minimum of 4.5 : 1 on white.
double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrastOnWhite(Color c) => 1.05 / (_luminance(c) + 0.05);

void main() {
  test('light accents become readable text colours', () {
    final lights = <Color>[
      Colors.green, Colors.red, Colors.orange, Colors.blue, Colors.grey,
      Colors.grey.shade400, Colors.amber, Colors.teal,
      const Color(0xFF10B981), const Color(0xFFF59E0B), const Color(0xFFEF4444),
      const Color(0xFF3B82F6), const Color(0xFF94A3B8), const Color(0xFFF97316),
    ];
    for (final c in lights) {
      expect(_contrastOnWhite(c), lessThan(4.5), reason: '$c should be one of the faded ones');
      final dark = readableText(c);
      expect(_contrastOnWhite(dark), greaterThanOrEqualTo(4.5), reason: '$c → $dark');
    }
  });

  test('other colours are left alone', () {
    expect(readableText(Colors.white), Colors.white);
    expect(readableText(Colors.black87), Colors.black87);
    expect(readableText(const Color(0xFF1E293B)), const Color(0xFF1E293B));
  });
}
