import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

const supabaseUrl = 'https://hrlciruepdstrvtsuoyr.supabase.co';
const apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhybGNpcnVlcGRzdHJ2dHN1b3lyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDA4MjgsImV4cCI6MjA5ODY3NjgyOH0.-FqYflyY-0333oNlC5clOpcOm_E60R6e9WULp_xZHEo';

/// Translate English text to Tamil using free Google Translate API
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
      // Response is nested array: [[["translated","original",null,null,10]],null,"en"]
      if (data is List && data.isNotEmpty && data[0] is List) {
        final translations = data[0] as List;
        if (translations.isNotEmpty && translations[0] is List) {
          return (translations[0] as List)[0] as String;
        }
      }
    }
    
    // Fallback: return original text
    return text;
  } catch (e) {
    print('Translation error for "$text": $e');
    return text;
  }
}

/// Batch translate multiple texts
Future<Map<String, String>> batchTranslate(Map<String, String> englishNames) async {
  final tamilMap = <String, String>{};
  
  // Translate in batches of 5 (API limit per request)
  final entries = englishNames.entries.toList();
  for (var i = 0; i < entries.length; i += 5) {
    final batch = entries.sublist(i, (i + 5).clamp(0, entries.length));
    
    for (final entry in batch) {
      final tamil = await translateToTamil(entry.value);
      tamilMap[entry.key] = tamil;
      print('  ${entry.value} -> $tamil');
      
      // Small delay to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    print('Translated ${batch.length}/${entries.length} products');
  }
  
  return tamilMap;
}

void main() async {
  print('=== Tamil Name Translator ===\n');
  
  // Step 1: Fetch only products WITHOUT Tamil names (tamil_name IS NULL)
  print('Fetching untranslated products from database...');
  final response = await http.get(
    Uri.parse('$supabaseUrl/rest/v1/products?select=id,name&tamil_name=is.null&order=name&limit=1100'),
    headers: {
      'apikey': apiKey,
      'Authorization': 'Bearer $apiKey',
    },
  );
  
  final products = jsonDecode(response.body) as List;
  print('Untranslated products: ${products.length}\n');
  
  // Step 2: Build English name map
  final englishNames = <String, String>{};
  for (final p in products) {
    final id = p['id'] as String;
    final name = p['name'] as String;
    englishNames[id] = name;
  }
  
  // Step 3: Translate to Tamil
  print('Translating to Tamil...');
  final tamilNames = await batchTranslate(englishNames);
  print('\nTranslation complete: ${tamilNames.length} products translated\n');
  
  // Step 4: Update database in batches
  print('Updating database...');
  final entries = tamilNames.entries.toList();
  var updated = 0;
  
  for (var i = 0; i < entries.length; i += 50) {
    final batch = entries.sublist(i, (i + 50).clamp(0, entries.length));
    final updateData = batch.map((e) => {
      'id': e.key,
      'tamil_name': e.value,
    }).toList();
    
    final body = jsonEncode({'products_json': updateData});
    
    try {
      final updateResponse = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/rpc/update_tamil_names'),
        headers: {
          'apikey': apiKey,
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      
      if (updateResponse.statusCode == 200 || updateResponse.statusCode == 204) {
        updated += batch.length;
        print('Updated $updated/${entries.length} products');
      } else {
        print('Batch update failed: ${updateResponse.statusCode}');
      }
    } catch (e) {
      print('Batch update error: $e');
    }
    
    // Small delay between batches
    await Future.delayed(const Duration(milliseconds: 300));
  }
  
  print('\nDone! Updated $updated products with Tamil names.');
  
  // Step 5: Verify a few products
  print('\nVerification:');
  final verifyResponse = await http.get(
    Uri.parse('$supabaseUrl/rest/v1/products?select=name,tamil_name&limit=5'),
    headers: {
      'apikey': apiKey,
      'Authorization': 'Bearer $apiKey',
    },
  );
  final verifyProducts = jsonDecode(verifyResponse.body) as List;
  for (final p in verifyProducts) {
    print('  ${p['name']} -> ${p['tamil_name']}');
  }
}
