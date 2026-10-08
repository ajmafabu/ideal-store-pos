import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/config/desktop_billing_provider.dart';
import 'package:ideal_store_pos/services/update_service.dart';

/// The updater must never leave a half-updated app, and must not restart the
/// app while a bill is open. The script tests run the real .bat, so they only
/// run on Windows (CI job "Updater script on Windows").
void main() {
  group('Update waits for open bills', () {
    test('an empty till does not block the update', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(desktopBillingProvider.notifier).hasOpenBills, isFalse);
    });

    test('a bill on screen blocks it; a held bill (saved on disk) does not', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final billing = container.read(desktopBillingProvider.notifier);
      billing.addItem(DesktopCartItem(productId: 'p', name: 'Rice', price: 50, qty: 1, unit: 'pcs'));
      expect(billing.hasOpenBills, isTrue);
      expect(billing.autoHoldCurrentSession(), isTrue);
      expect(billing.heldBills, hasLength(1));
      expect(billing.hasOpenBills, isFalse);
    });
  });

  group('Install script on Windows', () {
    const exe = 'pos_update_test_app.exe';
    late Directory app;
    late Directory source;

    String read(String rel) => File('${app.path}\\$rel').readAsStringSync();
    void write(Directory dir, String rel, String text) {
      final f = File('${dir.path}\\$rel');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(text);
    }

    setUp(() {
      app = Directory.systemTemp.createTempSync('pos_app');
      // a real, harmless exe stands in for the app (the script starts it)
      File('${Platform.environment['SystemRoot']}\\System32\\whoami.exe').copySync('${app.path}\\$exe');
      write(app, 'flutter_windows.dll', 'old dll');
      write(app, 'data\\app.so', 'old app');
      source = Directory('${app.path}\\_update')..createSync();
      File('${app.path}\\$exe').copySync('${source.path}\\$exe');
      write(source, 'flutter_windows.dll', 'new dll, a bit longer');
      write(source, 'data\\app.so', 'new app, a bit longer');
    });

    tearDown(() {
      Process.runSync('attrib', ['-R', '${app.path}\\*', '/S']);
      app.deleteSync(recursive: true);
    });

    Future<void> runScript() async {
      final bat = File('${app.path}_install.bat');   // next to the app folder, like %TEMP% in real use
      bat.writeAsStringSync(UpdateService.buildInstallScript(sourceDir: source.path, appDir: app.path, exeName: exe));
      // the exit code is not checked: the script deletes itself at the end,
      // which cmd may report as an error; the files below are what matters
      final r = await Process.run('cmd.exe', ['/c', bat.path]);
      if (bat.existsSync()) bat.deleteSync();
      final log = File('${Platform.environment['TEMP']}\\update_install.log');
      printOnFailure('${r.stdout}\n${r.stderr}\n${log.existsSync() ? log.readAsStringSync() : ''}');
    }

    test('a normal update replaces every file and cleans up', () async {
      await runScript();
      expect(read('flutter_windows.dll'), 'new dll, a bit longer');
      expect(read('data\\app.so'), 'new app, a bit longer');
      expect(File('${app.path}\\$exe').existsSync(), isTrue);
      expect(File('${app.path}\\$exe.old').existsSync(), isFalse);
      expect(Directory('${app.path}\\_backup').existsSync(), isFalse);
      expect(Directory('${app.path}\\_update').existsSync(), isFalse);
    });

    test('a copy that fails half-way puts every old file back', () async {
      // a read-only file in a sub-folder makes xcopy fail after it has
      // already replaced the files at the top level
      Process.runSync('attrib', ['+R', '${app.path}\\data\\app.so']);
      await runScript();
      expect(read('flutter_windows.dll'), 'old dll');
      expect(read('data\\app.so'), 'old app');
      expect(File('${app.path}\\$exe').existsSync(), isTrue);
      expect(File('${app.path}\\$exe.old').existsSync(), isFalse);
      expect(Directory('${app.path}\\_backup').existsSync(), isFalse);
    });

    test('an update without the new exe changes nothing', () async {
      File('${source.path}\\$exe').deleteSync();
      await runScript();
      expect(read('flutter_windows.dll'), 'old dll');
      expect(read('data\\app.so'), 'old app');
      expect(File('${app.path}\\$exe').existsSync(), isTrue);
      expect(Directory('${app.path}\\_update').existsSync(), isFalse);
    });
  }, skip: !Platform.isWindows ? 'runs the real .bat: Windows only' : false);
}
