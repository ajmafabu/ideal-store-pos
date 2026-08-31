# Plan: Fixes 6-10 — Accounting Improvements

## Fix 6: Add IGST for inter-state

### Files to modify:
1. **`lib/models/sale.dart`** — Add `igstAmount`, `cgstAmount`, `sgstAmount` fields to `Sale` class
   - Add fields to constructor (with defaults of 0)
   - Add to `fromJson`, `toJson`, `toInsertJson`, `copyWith`

2. **`lib/models/profile.dart`** — Add `stateCode` field
   - Add `String? stateCode` to constructor
   - Add to `fromJson` and `toJson`

3. **`lib/services/auth_service.dart`** — Include `state_code` in profile query
   - Add `state_code` to the `.select()` string at line 17

4. **`lib/models/customer.dart`** — Add `stateCode` field
   - Add `String? stateCode` to constructor
   - Add to `fromJson`, `toJson`, `toInsertJson`

5. **`lib/screens/desktop/desktop_billing_screen.dart`** — Calculate IGST vs CGST/SGST in `_saveSale`
   - In `_saveSale` (line 510), before creating the `Sale` object:
     - Query shop state_code from profile (`ref.read(profileProvider).value?.stateCode`)
     - Query customer state_code if customer is selected
     - Compare states → if different, set `igstAmount = totalGst`; else split into `cgstAmount`/`sgstAmount`
   - Pass the calculated values to the `Sale` constructor
   - Add a helper `_getCustomerState` method that queries `customers.state_code`

---

## Fix 7: Add aging analysis

### Files to modify:
1. **`lib/services/customer_service.dart`** — Add `getReceivablesAging()` method
   ```dart
   Future<List<Map<String, dynamic>>> getReceivablesAging() async {
     final response = await _supabase.rpc('get_receivables_aging');
     return (response as List).map((e) => Map<String, dynamic>.from(e)).toList();
   }
   ```

2. **`lib/screens/admin/reports_screen.dart`** — Add aging analysis section
   - Add a new card after the "Returns & Damaged" section (around line 323)
   - Use `FutureBuilder` to call `getReceivablesAging()` and display results in a table/card format
   - Show columns: Customer, Total Due, Current, 30 days, 60 days, 90 days, Over 90

---

## Fix 8: Save batch_number to inventory

### Files to check/modify:
1. **`lib/services/purchase_service.dart`** — Review `add_inventory_batch` RPC call (line 35-41)
   - **Already correct**: The code already passes `p_batch_number: item.batchNumber` and `p_expiry_date: item.expiryDate?.toIso8601String().split('T').first`
   - No changes needed — this fix is already implemented.

---

## Fix 9: Add payment reminders

### Files to modify:
1. **`lib/services/customer_service.dart`** — Add `getOverduePayments()` method
   ```dart
   Future<List<Map<String, dynamic>>> getOverduePayments() async {
     final response = await _supabase
         .from('sales')
         .select('id, customer_id, final_amount, due_amount, due_date, created_at')
         .eq('is_credit', true)
         .gt('due_amount', 0)
         .lt('due_date', DateTime.now().toIso8601String())
         .order('due_date');
     return (response as List).cast<Map<String, dynamic>>();
   }
   ```

2. **`lib/screens/admin/customer_screen.dart`** — Add overdue payment reminders
   - Add a `_checkOverduePayments()` method called from `initState`
   - Show a banner/alert at the top of the customer list when there are overdue payments
   - Display count of overdue payments and total overdue amount

---

## Fix 10: Improve P&L statement

### Files to modify:
1. **`lib/screens/admin/reports_screen.dart`** — Restructure P&L display
   - Replace the existing "Profit Summary" card (lines 272-290) with a proper P&L breakdown:
     - Sales Revenue (totalSales)
     - Less: Cost of Goods Sold (totalPurchases) → this represents purchase cost
     - = Gross Profit (sales - purchases)
     - Less: Expenses by category (iterate expensesByCategory)
     - = Net Profit (gross profit - expenses)
   - This matches the standard accounting P&L format
   - The `get_monthly_profit` SQL is already fixed in the migration — the reports_screen uses its own Dart-based calculation which is already correct

---

## Summary of changes by file:

| File | Fixes |
|------|-------|
| `lib/models/sale.dart` | Fix 6 |
| `lib/models/profile.dart` | Fix 6 |
| `lib/models/customer.dart` | Fix 6 |
| `lib/services/auth_service.dart` | Fix 6 |
| `lib/screens/desktop/desktop_billing_screen.dart` | Fix 6 |
| `lib/services/customer_service.dart` | Fix 7, Fix 9 |
| `lib/screens/admin/reports_screen.dart` | Fix 7, Fix 10 |
| `lib/screens/admin/customer_screen.dart` | Fix 9 |
| `lib/services/purchase_service.dart` | Fix 8 (no changes needed) |

## Execution order:
1. Fix 6 (Sale model, Profile model, Customer model, auth service, billing screen)
2. Fix 7 (customer service + reports screen)
3. Fix 8 (verify only — already implemented)
4. Fix 9 (customer service + customer screen)
5. Fix 10 (reports screen P&L restructure)
