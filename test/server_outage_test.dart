import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ideal_store_pos/config/hive_adapter.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/services/offline_service.dart';
import 'package:ideal_store_pos/services/sale_service.dart';
import 'package:ideal_store_pos/utils/error_messages.dart';
import 'package:ideal_store_pos/utils/network_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase having trouble must never stop billing (owner, 25 Oct 2026:
/// "some time server issues at that time we cant billing").
void main() {
  PostgrestException pg(String code, [String message = 'x']) => PostgrestException(message: message, code: code);

  group('server trouble is not a refusal', () {
    test('gateway pages and database outages: keep the bill and send it later', () {
      for (final code in ['500', '502', '503', '504', '520', '522', '524', '408', '429']) {
        expect(isNetworkError(pg(code, '<html>Bad gateway</html>')), isTrue, reason: code);
      }
      for (final code in ['PGRST000', 'PGRST001', 'PGRST002', 'PGRST003', '08006', '53300', '57P01', '57014']) {
        expect(isNetworkError(pg(code)), isTrue, reason: code);
      }
      expect(isNetworkError(pg('', '<!DOCTYPE html><html>Cloudflare</html>')), isTrue);
    });

    test('real refusals are still shown, never queued', () {
      for (final code in [
        'P0001',
        'P0002',
        '42501',
        '23505',
        '23514',
        '23503',
        '400',
        '401',
        '404',
        'PGRST202',
        '42883',
      ]) {
        expect(isNetworkError(pg(code)), isFalse, reason: code);
      }
    });

    test('the login server failing keeps you signed in; a wrong password is a refusal', () {
      expect(isNetworkError(AuthRetryableFetchException(statusCode: '503')), isTrue);
      expect(isNetworkError(AuthApiException('Invalid login credentials', statusCode: '400')), isFalse);
      expect(ErrorMessages.parse(AuthRetryableFetchException(statusCode: '503')), isNot(contains('Invalid')));
    });

    test('the words shown during server trouble', () {
      expect(serverMessage(pg('503')), serverTroubleMessage);
      expect(ErrorMessages.parse(pg('502', '<html>')), serverTroubleMessage);
    });
  });

  group('billing while Supabase is down', () {
    late Directory dir;
    late HttpServer server;
    var status = 503;
    var hits = 0;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('hive_outage_');
      Hive.init(dir.path);
      HiveAdapter.useCipherForTests(HiveAesCipher(List<int>.generate(32, (i) => i)));
      final offline = OfflineService();
      if (!offline.isReady) await offline.init();
      // a stand-in for Supabase: answers like a broken gateway, or with a refusal
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        hits++;
        await utf8.decoder.bind(req).join();
        req.response.statusCode = status;
        if (status == 400) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'code': 'P0001', 'message': 'Your account is not active.'}));
        } else {
          req.response.headers.contentType = ContentType.html;
          req.response.write('<html><body>503 Service Unavailable</body></html>');
        }
        await req.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    setUp(() async {
      await OfflineService().pendingBox.clear();
      ServerHealth.markUp();
      hits = 0;
    });

    Sale sale(String id) => Sale(
      id: id,
      items: [CartItem(productId: 'p', name: 'Soap', price: 30, qty: 1, unit: 'pcs')],
      totalAmount: 30,
      discount: 0,
      totalDiscount: 0,
      finalAmount: 30,
      paymentMethod: 'cash',
      createdBy: 'u',
      createdAt: DateTime.utc(2026, 10, 25, 6),
    );

    SaleService service() => SaleService(
      client: SupabaseClient('http://127.0.0.1:${server.port}', 'test-key'),
      offlineService: OfflineService(),
    );

    test('a 503 from Supabase: the bill is saved on the device, not refused', () async {
      status = 503;
      await expectLater(
        service().createSale(sale('00000000-0000-4000-8000-0000000000a1')),
        throwsA(isA<SaleSavedOffline>()),
      );
      expect(OfflineService().pendingCount, 1);
      expect(ServerHealth.likelyDown, isTrue);
    });

    test('the next bills go straight to the device for a minute (no waiting at the counter)', () async {
      status = 503;
      await expectLater(
        service().createSale(sale('00000000-0000-4000-8000-0000000000a2')),
        throwsA(isA<SaleSavedOffline>()),
      );
      final before = hits;
      await expectLater(
        service().createSale(sale('00000000-0000-4000-8000-0000000000a3')),
        throwsA(isA<SaleSavedOffline>()),
      );
      expect(hits, before, reason: 'the second bill did not try the server');
      expect(OfflineService().pendingCount, 2);
    });

    test('a real refusal is still shown and nothing is queued', () async {
      status = 400;
      await expectLater(
        service().createSale(sale('00000000-0000-4000-8000-0000000000a4')),
        throwsA(isA<PostgrestException>()),
      );
      expect(OfflineService().pendingCount, 0);
      expect(ServerHealth.likelyDown, isFalse);
    });
  });
}
