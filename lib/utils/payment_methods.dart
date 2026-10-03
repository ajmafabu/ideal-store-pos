/// One vocabulary for payment methods across both billing screens, purchases,
/// expenses and payments (#12). Mirrors `norm_payment_method()` in the database.
///
///   cash   – cash drawer
///   upi    – GPay/PhonePe/Paytm/QR (lands in the bank account)
///   bank   – card, NEFT/IMPS/RTGS, cheque (bank account)
///   credit – nothing paid now (customer/supplier owes)
///   split  – part cash, part UPI (sale only)
class PaymentMethods {
  static const cash = 'cash';
  static const upi = 'upi';
  static const bank = 'bank';
  static const credit = 'credit';
  static const split = 'split';

  static String normalize(String? method) {
    final m = (method ?? '').trim().toLowerCase();
    if (m.isEmpty || m == 'cash' || m == 'cod') return cash;
    if (const {'upi', 'digital', 'online', 'gpay', 'google pay', 'phonepe', 'paytm', 'qr', 'wallet'}.contains(m)) {
      return upi;
    }
    if (const {'bank', 'card', 'debit card', 'credit card', 'neft', 'imps', 'rtgs', 'cheque', 'check', 'transfer', 'bank transfer'}
        .contains(m)) {
      return bank;
    }
    if (m == 'credit' || m == 'udhaar' || m == 'due') return credit;
    if (m == 'split' || m == 'mixed') return split;
    return m;
  }

  /// Which money account the method moves: 'cash' or 'bank'.
  static String accountType(String? method) {
    final m = normalize(method);
    return (m == upi || m == bank) ? 'bank' : 'cash';
  }

  static String label(String? method) {
    switch (normalize(method)) {
      case upi:
        return 'UPI';
      case bank:
        return 'Bank';
      case credit:
        return 'Credit';
      case split:
        return 'Split';
      default:
        return 'Cash';
    }
  }

  /// Choices offered when money is paid or received (no credit/split).
  static const moneyMethods = [cash, upi, bank];
}
