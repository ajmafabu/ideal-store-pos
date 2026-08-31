import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

const supabaseUrl = 'https://hrlciruepdstrvtsuoyr.supabase.co';
const apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo';

Future<String> translateToTamil(String text) async {
  if (text.isEmpty) return text;
  try {
    final encoded = Uri.encodeComponent(text);
    final url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ta&dt=t&q=$encoded';
    final response = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': 'Mozilla/5.0'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List && data.isNotEmpty && data[0] is List) {
        final translations = data[0] as List;
        if (translations.isNotEmpty && translations[0] is List) {
          return (translations[0] as List)[0] as String;
        }
      }
    }
    return text;
  } catch (e) {
    print('  Translation error: $e');
    return text;
  }
}

void main() async {
  print('=== Tamil Name Translator v2 ===\n');

  // Step 1: Clear ALL existing Tamil names
  print('Step 1: Clearing all Tamil names...');
  final allProducts = <Map<String, dynamic>>[];
  var offset = 0;
  while (true) {
    final resp = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/products?select=id&limit=1000&offset=$offset'),
      headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey'},
    );
    final batch = jsonDecode(resp.body) as List;
    if (batch.isEmpty) break;
    allProducts.addAll(batch.map((p) => {'id': p['id'], 'tamil_name': null}));
    offset += 1000;
  }
  print('  Found ${allProducts.length} products');

  for (var i = 0; i < allProducts.length; i += 50) {
    final batch = allProducts.sublist(i, (i + 50).clamp(0, allProducts.length));
    final body = jsonEncode({'products_json': batch});
    await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/update_tamil_names'),
      headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: body,
    );
  }
  print('  Cleared!\n');

  // Step 2: Fetch all products again
  print('Step 2: Fetching all products...');
  final products = <Map<String, dynamic>>[];
  offset = 0;
  while (true) {
    final resp = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/products?select=id,name&order=name&limit=1000&offset=$offset'),
      headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey'},
    );
    final batch = jsonDecode(resp.body) as List;
    if (batch.isEmpty) break;
    products.addAll(batch.map((p) => {'id': p['id'] as String, 'name': p['name'] as String}));
    offset += 1000;
  }
  print('  Total products: ${products.length}\n');

  // Step 3: Translate to Tamil using Google Translate
  print('Step 3: Translating to Tamil via Google Translate...');
  var translated = 0;

  for (var i = 0; i < products.length; i += 50) {
    final batch = products.sublist(i, (i + 50).clamp(0, products.length));
    final updates = <Map<String, dynamic>>[];

    for (final p in batch) {
      final tamil = await translateToTamil(p['name'] as String);
      updates.add({'id': p['id'], 'tamil_name': tamil});
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Update via RPC
    final body = jsonEncode({'products_json': updates});
    final resp = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/update_tamil_names'),
      headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: body,
    );

    translated += batch.length;
    print('  Translated $translated/${products.length} products (${resp.statusCode})');
  }

  // Step 4: Verify
  print('\nVerification (random samples):');
  final verifyResp = await http.get(
    Uri.parse('$supabaseUrl/rest/v1/products?select=name,tamil_name&offset=200&limit=10'),
    headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey'},
  );
  final verify = jsonDecode(verifyResp.body) as List;
  for (final p in verify) {
    print('  ${p['name']} -> ${p['tamil_name']}');
  }
}
