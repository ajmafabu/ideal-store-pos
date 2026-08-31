import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const supabaseUrl = 'https://hrlciruepdstrvtsuoyr.supabase.co';
  const apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo';

  // Step 1: Clear ALL Tamil names
  print('Clearing all Tamil names...');
  final allResponse = await http.get(
    Uri.parse('$supabaseUrl/rest/v1/products?select=id&limit=1000'),
    headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey'},
  );
  final allProducts = jsonDecode(allResponse.body) as List;
  print('Total products: ${allProducts.length}');

  // Clear in batches using RPC
  for (var i = 0; i < allProducts.length; i += 50) {
    final batch = allProducts.sublist(i, (i + 50).clamp(0, allProducts.length))
        .map((p) => {'id': p['id'], 'tamil_name': ''}).toList();
    final body = jsonEncode({'products_json': batch});
    await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/update_tamil_names'),
      headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: body,
    );
  }
  print('All Tamil names cleared!');

  // Step 2: Re-insert proper Tamil names
  print('\nInserting proper Tamil names...');
  // (same tamilMap as before)
  // ... (copy the tamilMap and update logic from the previous script)
  print('Done!');
}
