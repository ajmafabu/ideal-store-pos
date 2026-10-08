/// Quantities can be decimal (1.5 kg, 0.25 kg). Whole numbers print without
/// decimals ("2", not "2.0"); others with up to 3 decimals ("1.5", "0.25").
String formatQty(num qty) {
  if (qty == qty.roundToDouble()) return qty.toInt().toString();
  return qty.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}
