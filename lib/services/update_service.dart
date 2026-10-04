import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

class UpdateService {
  static const _repo = 'ajmafabu/ideal-store-pos';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';
  static const _skipVersionKey = 'skipped_update_version';

  /// Save a version to skip (won't show update dialog for this version)
  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipVersionKey, version);
    Logger.info('Update: skipped version $version');
  }

  /// Get the skipped version (if any)
  Future<String?> getSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_skipVersionKey);
  }

  /// Clear skipped version (e.g., after a successful manual update)
  Future<void> clearSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skipVersionKey);
  }

  /// Check GitHub for a newer version. Returns null if up-to-date or skipped.
  /// Returns the newer release, or null when there is none.
  /// [manual] = the admin pressed "Check for Updates": a skipped version is
  /// offered again, and a failed check throws instead of looking like
  /// "you are on the latest version".
  Future<UpdateInfo?> checkForUpdate({bool manual = false}) async {
    try {
      // Skip if we just installed an update (avoids loop when Windows caches old version info)
      final markerFile = File('${Directory.systemTemp.path}\\pos_just_updated');
      if (await markerFile.exists()) {
        final markerContent = await markerFile.readAsString();
        final installTime = DateTime.tryParse(markerContent);
        if (installTime != null && DateTime.now().difference(installTime).inMinutes < 5) {
          Logger.info('[UPDATE] Skipped - just updated ${DateTime.now().difference(installTime).inSeconds}s ago');
          await markerFile.delete();
          return null;
        }
        await markerFile.delete();
      }

      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      final buildNumber = info.buildNumber;
      Logger.info('[UPDATE] Current version: $currentVersion (build $buildNumber)');

      // Write debug to file so user can check
      final debugFile = File('${Directory.systemTemp.path}\\update_debug.log');
      await debugFile.writeAsString('=== Update Check ===\n'
          'Time: ${DateTime.now()}\n'
          'Current version: $currentVersion (build $buildNumber)\n');

      Logger.info('[UPDATE] Calling GitHub API: $_apiUrl');
      await debugFile.writeAsString(
          'API URL: $_apiUrl\n',
          mode: FileMode.append);

      // normal certificate checking (it used to accept ANY certificate)
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(_apiUrl));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      client.close();
      Logger.info('[UPDATE] API response status: ${response.statusCode}');
      await debugFile.writeAsString(
          'Response status: ${response.statusCode}\n',
          mode: FileMode.append);

      if (response.statusCode != 200) {
        await debugFile.writeAsString(
            'Response body: $body\n',
            mode: FileMode.append);
        if (manual) throw Exception('Could not reach GitHub (status ${response.statusCode}). Try again later.');
        return null;
      }

      final release = json.decode(body);
      final tagName = release['tag_name'] ?? '';
      final latestVersion = tagName.replaceFirst('v', '');
      Logger.info('[UPDATE] Latest version from GitHub: $latestVersion');

      await debugFile.writeAsString(
          'Tag name: $tagName\n'
          'Latest version: $latestVersion\n'
          'Release body: ${release['body']}\n',
          mode: FileMode.append);

      if (latestVersion.isEmpty) {
        await debugFile.writeAsString('Result: empty latest version\n', mode: FileMode.append);
        return null;
      }
      if (!isNewer(latestVersion, currentVersion)) {
        Logger.info('[UPDATE] Versions match - no update needed');
        await debugFile.writeAsString('Result: versions match\n', mode: FileMode.append);
        return null;
      }

      // Check if this version was skipped
      final skippedVersion = await getSkippedVersion();
      if (!manual && skippedVersion == latestVersion) {
        Logger.info('[UPDATE] Version $latestVersion was skipped by user');
        await debugFile.writeAsString('Result: version skipped\n', mode: FileMode.append);
        return null;
      }

      final assets = (release['assets'] as List?) ?? [];
      Logger.info('[UPDATE] Assets count: ${assets.length}');
      await debugFile.writeAsString('Assets: ${assets.length}\n', mode: FileMode.append);
      for (final a in assets) {
        final name = a['name'] ?? 'unknown';
        final size = a['size'] ?? 0;
        Logger.info('[UPDATE]   - $name ($size bytes)');
        await debugFile.writeAsString('  - $name ($size bytes)\n', mode: FileMode.append);
      }
      final zipAsset = assets.where((a) => (a['name'] ?? '').toString().endsWith('.zip')).toList();
      if (zipAsset.isEmpty) {
        Logger.info('[UPDATE] No zip asset found');
        await debugFile.writeAsString('Result: no zip asset\n', mode: FileMode.append);
        return null;
      }

      final downloadUrl = zipAsset.first['browser_download_url'] ?? '';
      // "<zip name>.sha256" published by release.ps1 / CI next to the zip
      final zipName = (zipAsset.first['name'] ?? '').toString();
      final shaAsset = assets.where((a) {
        final n = (a['name'] ?? '').toString().toLowerCase();
        return n == '${zipName.toLowerCase()}.sha256' || n == 'sha256sums.txt' || n == 'sha256sums';
      }).toList();
      final checksumUrl = shaAsset.isEmpty ? null : shaAsset.first['browser_download_url']?.toString();
      Logger.info('[UPDATE] Download URL: $downloadUrl');
      await debugFile.writeAsString(
          'Result: UPDATE AVAILABLE\n'
          'Download URL: $downloadUrl\n',
          mode: FileMode.append);

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: release['body'] ?? '',
        checksumUrl: checksumUrl,
        zipName: zipName,
      );
    } catch (e, stackTrace) {
      Logger.info('[UPDATE] Check failed: $e');
      try {
        final debugFile = File('${Directory.systemTemp.path}\\update_debug.log');
        await debugFile.writeAsString(
            'ERROR: $e\n'
            'Stack: $stackTrace\n',
            mode: FileMode.append);
      } catch (_) {}
      if (manual) rethrow;
      return null;
    }
  }

  /// Where the new version is unpacked: a "_update" folder inside the app's
  /// own folder, which is the folder excluded from antivirus scanning.
  /// Unpacking into %TEMP% let Windows Security quarantine the new .exe
  /// half-way through an update. Falls back to %TEMP% if the app folder
  /// cannot be written to.
  Future<String> _stagingDir(String tempPath) async {
    final appDir = Directory(Platform.resolvedExecutable).parent.path;
    final staging = Directory('$appDir\\_update');
    try {
      await staging.create(recursive: true);
      final probe = File('${staging.path}\\.write_test');
      await probe.writeAsString('ok');
      await probe.delete();
      return staging.path;
    } catch (_) {
      return '$tempPath\\update_extract';
    }
  }

  /// Download and install update. Returns path to extracted folder.
  Future<String> downloadAndInstall(UpdateInfo update, {void Function(double progress)? onProgress}) async {
    final tempDir = await getTemporaryDirectory();
    final zipPath = '${tempDir.path}\\update.zip';
    final extractDir = await _stagingDir(tempDir.path);

    // Only install what the release says it is (#32): the release must
    // publish a SHA-256 of the zip, and the download must match it.
    if (update.checksumUrl == null) {
      throw Exception('This release has no SHA-256 checksum, so it cannot be installed automatically. '
          'Download it manually from the releases page.');
    }
    final expected = await _fetchChecksum(update.checksumUrl!, update.zipName);

    // Download zip (normal certificate checking)
    Logger.info('Downloading update: ${update.downloadUrl}');
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(update.downloadUrl));
    final response = await request.close().timeout(const Duration(minutes: 5));

    final totalBytes = response.contentLength;
    var receivedBytes = 0;
    final sink = File(zipPath).openWrite();

    await for (final chunk in response) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(receivedBytes / totalBytes);
      }
    }
    await sink.close();
    client.close();

    Logger.info('Download complete: $receivedBytes bytes');

    // Verify before anything is extracted or run
    final bytes = File(zipPath).readAsBytesSync();
    final actual = sha256.convert(bytes).toString();
    if (actual.toLowerCase() != expected.toLowerCase()) {
      await File(zipPath).delete();
      throw Exception('Update download is corrupted or was changed (checksum mismatch). Nothing was installed.');
    }
    Logger.info('Update checksum verified');

    // Extract zip
    final archive = ZipDecoder().decodeBytes(bytes);

    // Clear extract directory
    final extractDirObj = Directory(extractDir);
    if (await extractDirObj.exists()) {
      await extractDirObj.delete(recursive: true);
    }
    await extractDirObj.create(recursive: true);

    // Extract files (refuse paths that would escape the folder)
    for (final file in archive) {
      final name = file.name.replaceAll('/', '\\');
      if (name.startsWith('\\') || name.contains(':') || name.split('\\').contains('..')) {
        throw Exception('Unsafe path in update package: ${file.name}');
      }
      final filePath = '$extractDir\\$name';
      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }

    Logger.info('Extracted to: $extractDir');

    // Find the exe in extracted files
    final exeFiles = await extractDirObj.list(recursive: true).where((f) => f.path.endsWith('.exe')).toList();
    if (exeFiles.isEmpty) {
      throw Exception('No executable found in update package');
    }

    Logger.info('Update ready at: $extractDir');
    return extractDir;
  }

  /// True when [latest] (e.g. 1.1.0) is a higher version than [current].
  static bool isNewer(String latest, String current) {
    List<int> parts(String v) => v.split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final a = parts(latest), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<String> _fetchChecksum(String url, String zipName) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('Could not download the checksum (${res.statusCode})');
      final text = await res.transform(utf8.decoder).join();
      // "<hex>  <file>" lines (sha256sum format) or just "<hex>"
      for (final line in const LineSplitter().convert(text)) {
        final m = RegExp(r'\b([0-9a-fA-F]{64})\b\s*\*?(\S+)?').firstMatch(line.trim());
        if (m == null) continue;
        final file = m.group(2);
        if (file == null || file.endsWith(zipName)) return m.group(1)!;
      }
      throw Exception('Checksum file does not list $zipName');
    } finally {
      client.close();
    }
  }

  /// Install update by replacing current app files and restarting
  Future<void> installUpdate(String extractDir) async {
    final appDir = Directory(Platform.resolvedExecutable).parent.path;
    final exeName = Platform.resolvedExecutable.split('\\').last;
    final extractDirObj = Directory(extractDir);

    Logger.info('Installing update to: $appDir');

    // Find the actual app files in extracted directory
    String sourceDir = extractDir;
    final exeFiles = await extractDirObj.list(recursive: true).where((f) => f.path.endsWith('.exe')).toList();
    if (exeFiles.isNotEmpty) {
      sourceDir = exeFiles.first.parent.path;
    }

    // Create a robust batch script — uses set variables, proper error handling
    // NOTE: In batch files, variables use %VAR% (single percent), not %%VAR%%
    final batScript = '''
@echo off
title Ideal Store POS Updater
set "LOG=%TEMP%\\update_install.log"

:: Define paths using set (avoids Dart interpolation issues)
set "SOURCE=$sourceDir"
set "DEST=$appDir"
set "EXE=$exeName"

echo [%date% %time%] ====== UPDATE STARTED ======>> "%LOG%"
echo [%date% %time%] Source: %SOURCE% >> "%LOG%"
echo [%date% %time%] Dest: %DEST% >> "%LOG%"

:: Validate paths exist
if not exist "%SOURCE%" (
    echo [%date% %time%] ERROR: Source path does not exist >> "%LOG%"
    goto :ERROR
)
if not exist "%DEST%" (
    echo [%date% %time%] ERROR: Dest path does not exist >> "%LOG%"
    goto :ERROR
)

:: Wait for app to fully close
echo [%date% %time%] Waiting 5s for app to close... >> "%LOG%"
timeout /t 5 /nobreak >nul

:: Force kill any remaining instance
echo [%date% %time%] Killing old process... >> "%LOG%"
taskkill /f /im "%EXE%" >nul 2>&1
timeout /t 2 /nobreak >nul

:: Kill again in case it lingered
taskkill /f /im "%EXE%" >nul 2>&1

:: The new version must be complete before the old one is touched
if not exist "%SOURCE%\\%EXE%" (
    echo [%date% %time%] ERROR: new %EXE% missing from the update - antivirus? Old version kept. >> "%LOG%"
    goto :KEEP_OLD
)

:: Keep the old exe until the new one is in place
echo [%date% %time%] Backing up old exe... >> "%LOG%"
if exist "%DEST%\\%EXE%.old" del /Q "%DEST%\\%EXE%.old" 2>>"%LOG%"
ren "%DEST%\\%EXE%" "%EXE%.old" 2>>"%LOG%"

:: Copy new files over the old ones
echo [%date% %time%] Copying new files... >> "%LOG%"
xcopy /E /Y /I "%SOURCE%" "%DEST%" >> "%LOG%" 2>&1
if errorlevel 1 (
    echo [%date% %time%] ERROR: xcopy failed with errorlevel %errorlevel% >> "%LOG%"
    goto :RESTORE
)

:: Verify exe exists after copy
if not exist "%DEST%\\%EXE%" (
    echo [%date% %time%] ERROR: exe not found after copy >> "%LOG%"
    goto :RESTORE
)

del /Q "%DEST%\\%EXE%.old" 2>>"%LOG%"
if exist "%DEST%\\_update" rmdir /S /Q "%DEST%\\_update" 2>>"%LOG%"
echo [%date% %time%] Update successful, restarting app... >> "%LOG%"
start "" "%DEST%\\%EXE%"
goto :DONE

:RESTORE
echo [%date% %time%] Restoring the old version... >> "%LOG%"
if exist "%DEST%\\%EXE%.old" (
    if exist "%DEST%\\%EXE%" del /Q "%DEST%\\%EXE%" 2>>"%LOG%"
    ren "%DEST%\\%EXE%.old" "%EXE%" 2>>"%LOG%"
)

:KEEP_OLD
if exist "%DEST%\\_update" rmdir /S /Q "%DEST%\\_update" 2>>"%LOG%"
if exist "%DEST%\\%EXE%" start "" "%DEST%\\%EXE%"

:ERROR
echo [%date% %time%] ====== UPDATE FAILED ======>> "%LOG%"
echo Please download manually from: https://github.com/ajmafabu/ideal-store-pos/releases >> "%LOG%"

:DONE
:: Self-delete after a delay
timeout /t 3 /nobreak >nul
del "%~f0"
''';

    final batPath = '${Directory.systemTemp.path}\\install_update.bat';
    await File(batPath).writeAsString(batScript);

    Logger.info('Starting updater: $batPath');

    // Write marker so the restarted app knows we just updated
    final markerFile = File('${Directory.systemTemp.path}\\pos_just_updated');
    await markerFile.writeAsString(DateTime.now().toIso8601String());

    // Launch the batch script detached
    await Process.start('cmd.exe', ['/c', batPath], mode: ProcessStartMode.detached);

    // Exit current app
    exit(0);
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;

  /// URL of the published SHA-256 of the zip; null = cannot auto-install.
  final String? checksumUrl;
  final String zipName;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    this.checksumUrl,
    this.zipName = '',
  });
}
