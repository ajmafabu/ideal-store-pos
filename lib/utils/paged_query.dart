import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase returns at most 1000 rows per request, so a report that reads
/// raw rows (a busy month has more than 1000 bills) silently came up short.
/// This reads every page, in a stable order, and returns all rows.
///
/// [query] builds the filtered query; it is called once per page because a
/// query builder can only be sent once.
Future<List<Map<String, dynamic>>> fetchAllRows(
  PostgrestFilterBuilder<PostgrestList> Function() query, {
  String orderBy = 'id',
  bool ascending = true,
  int pageSize = 1000,
}) async {
  final rows = <Map<String, dynamic>>[];
  for (var from = 0;; from += pageSize) {
    var page = query().order(orderBy, ascending: ascending);
    // ties in orderBy would make pages overlap or skip rows
    if (orderBy != 'id') page = page.order('id', ascending: true);
    final batch = await page.range(from, from + pageSize - 1);
    rows.addAll(batch);
    if (batch.length < pageSize) return rows;
  }
}
