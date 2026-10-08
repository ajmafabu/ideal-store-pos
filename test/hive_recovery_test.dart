import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ideal_store_pos/config/hive_adapter.dart';

/// Opening the local data must never silently lose unsent bills
/// (HiveAdapter.openBoxSafely).
void main() {
  final keyA = HiveAesCipher(List<int>.generate(32, (i) => i));
  final keyB = HiveAesCipher(List<int>.generate(32, (i) => 255 - i));
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_recovery_test');
    Hive.init(dir.path);
    HiveAdapter.recoveredBoxes.clear();
    HiveAdapter.recoveryDir = null;
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> saveBills(HiveAesCipher key) async {
    final box = await Hive.openBox<Map>('pending_sales', encryptionCipher: key);
    await box.put('bill-1', {'total': 120});
    await box.put('bill-2', {'total': 80});
    await box.close();
  }

  File boxFile(String folder) => File('$folder${Platform.pathSeparator}pending_sales.hive');

  test('healthy data opens unchanged and leaves no copies behind', () async {
    await saveBills(keyA);
    final box = await HiveAdapter.openBoxSafely('pending_sales', keyA, dir.path);
    expect(box.length, 2);
    expect(HiveAdapter.recoveredBoxes, isEmpty);
    expect(dir.listSync().where((f) => f.path.endsWith('.before_open')), isEmpty);
    expect(Directory('${dir.path}${Platform.pathSeparator}hive_recovery').existsSync(), isFalse);
  });

  test('a changed key keeps the original file, so the bills can be recovered', () async {
    await saveBills(keyA);
    final sizeBefore = boxFile(dir.path).lengthSync();

    final box = await HiveAdapter.openBoxSafely('pending_sales', keyB, dir.path);
    expect(box.length, 0); // Hive cannot read them with the new key...
    expect(HiveAdapter.recoveredBoxes, ['pending_sales']); // ...but it is reported
    final kept = boxFile(HiveAdapter.recoveryDir!);
    expect(kept.lengthSync(), sizeBefore);
    await Hive.close();

    // with the old key the kept copy still holds both bills
    final restore = await Directory.systemTemp.createTemp('hive_restore');
    try {
      await kept.copy(boxFile(restore.path).path);
      Hive.init(restore.path);
      final recovered = await Hive.openBox<Map>('pending_sales', encryptionCipher: keyA);
      expect(recovered.length, 2);
      expect(recovered.get('bill-1'), {'total': 120});
      await Hive.close();
    } finally {
      await restore.delete(recursive: true);
    }
  });

  test('a damaged file keeps its readable bills and a copy of the original', () async {
    await saveBills(keyA);
    final file = boxFile(dir.path);
    await file.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8, 9], mode: FileMode.append);
    final sizeBefore = file.lengthSync();

    final box = await HiveAdapter.openBoxSafely('pending_sales', keyA, dir.path);
    expect(box.length, 2);
    expect(HiveAdapter.recoveredBoxes, ['pending_sales']);
    expect(boxFile(HiveAdapter.recoveryDir!).lengthSync(), sizeBefore);
  });

  test('a new box opens normally', () async {
    final box = await HiveAdapter.openBoxSafely('pending_sales', keyA, dir.path);
    expect(box.isEmpty, isTrue);
    expect(HiveAdapter.recoveredBoxes, isEmpty);
  });
}
