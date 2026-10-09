/// Money paid at the counter together with each bill, for the running
/// balance of a customer or supplier (Money Flow tab, statement PDF).
///
/// QA test 8 Oct 2026, finding 14: the running balance added every bill as
/// owed — a fully paid ₹1,100 cash purchase and the ₹50 paid with a credit
/// purchase were never taken off, so it showed "Bal ₹1,150" when ₹0 was due.
///
/// Paid with the bill = total − what is still due − later payments linked to
/// that bill. [totalKey]: `total_amount` (purchases) or `final_amount`
/// (sales); [linkKey]: the payment column naming the bill (`purchase_id` /
/// `sale_id`). Returns bill id → amount (only amounts above 1 paisa).
Map<String, double> paidWithBill({
  required List<Map<String, dynamic>> bills,
  required List<Map<String, dynamic>> payments,
  required String totalKey,
  required String linkKey,
}) {
  double num0(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  final laterPaid = <String, double>{};
  for (final p in payments) {
    final id = p[linkKey]?.toString();
    if (id == null || id.isEmpty) continue;
    laterPaid[id] = (laterPaid[id] ?? 0) + num0(p['amount']);
  }

  final result = <String, double>{};
  for (final b in bills) {
    final id = b['id']?.toString() ?? '';
    final paid = num0(b[totalKey]) - num0(b['due_amount']) - (laterPaid[id] ?? 0);
    if (paid > 0.005) result[id] = paid;
  }
  return result;
}
