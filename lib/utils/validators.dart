/// Form validators used across the app (#27). Each returns null when the
/// value is acceptable, or a short message to show under the field.
class Validators {
  static final _gstin = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phone = RegExp(r'^(\+91[\s-]?)?[6-9][0-9]{9}$');
  static final _hsn = RegExp(r'^[0-9]{4}([0-9]{2}){0,2}$');

  static String? required(String? v, [String label = 'This field']) =>
      (v == null || v.trim().isEmpty) ? '$label is required' : null;

  /// A price or amount: a number, not negative (zero allowed when [allowZero]).
  static String? amount(String? v, {bool required = true, bool allowZero = false, String label = 'Amount'}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return required ? '$label is required' : null;
    final n = double.tryParse(t);
    if (n == null) return 'Enter a number, e.g. 45.50';
    if (n < 0) return '$label cannot be negative';
    if (!allowZero && n == 0) return '$label must be more than 0';
    return null;
  }

  /// A whole quantity of at least [min].
  static String? quantity(String? v, {int min = 1}) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return 'Enter a whole number';
    if (n < min) return 'Must be at least $min';
    return null;
  }

  /// Indian mobile number (10 digits starting 6–9, optional +91). Empty is allowed.
  static String? phone(String? v) {
    final t = (v ?? '').replaceAll(' ', '');
    if (t.isEmpty) return null;
    return _phone.hasMatch(t) ? null : 'Enter a 10-digit mobile number';
  }

  static String? email(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return _email.hasMatch(t) ? null : 'Enter a valid e-mail address';
  }

  /// 15-character GSTIN, e.g. 33ABCDE1234F1Z5. Empty is allowed.
  static String? gstin(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (t.isEmpty) return null;
    return _gstin.hasMatch(t) ? null : 'GSTIN must be 15 characters, e.g. 33ABCDE1234F1Z5';
  }

  /// HSN/SAC code of 4, 6 or 8 digits. Empty is allowed.
  static String? hsn(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return _hsn.hasMatch(t) ? null : 'HSN code must be 4, 6 or 8 digits';
  }

  /// Two-digit state code taken from a valid GSTIN, else null.
  static String? stateFromGstin(String? gstin) {
    final t = (gstin ?? '').trim().toUpperCase();
    return _gstin.hasMatch(t) ? t.substring(0, 2) : null;
  }
}
