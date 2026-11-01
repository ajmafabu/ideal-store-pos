import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The daily backup outside Supabase (25 Oct 2026).
void main() {
  test('the copy folder is remembered and can be cleared', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await BackupService.copyFolder(), isNull);
    await BackupService.setCopyFolder(r'G:\My Drive\IdealStore Backups ');
    expect(await BackupService.copyFolder(), r'G:\My Drive\IdealStore Backups');
    await BackupService.setCopyFolder('');
    expect(await BackupService.copyFolder(), isNull);
  });

  test('no second automatic backup within the day', () async {
    SharedPreferences.setMockInitialValues({
      'backup_last_auto': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
    });
    // a client that cannot be reached: a backup attempt would fail loudly
    final service = BackupService(client: SupabaseClient('http://127.0.0.1:9', 'key'));
    expect(await service.autoBackupIfDue(), isNull);
  });

  test('Supabase storage keeps only the newest 14 backups; other files are left alone', () {
    final names = [
      for (var d = 1; d <= 20; d++) 'backup_2026-10-${d.toString().padLeft(2, '0')}T21-00-00.json',
      'notes.txt',
    ]..shuffle();
    final remove = BackupService.cloudToRemove(names);
    expect(remove, hasLength(6));
    expect(remove, everyElement(matches(r'backup_2026-10-0[1-6]T')));
    expect(remove, isNot(contains('notes.txt')));
    expect(BackupService.cloudToRemove(names.take(5).toList()), isEmpty);
  });

  test('every table the database restores is in the backup', () {
    expect(
      BackupService.tables,
      containsAll(['products', 'sales', 'purchases', 'supplier_returns', 'stock_adjustments']),
    );
  });
}
