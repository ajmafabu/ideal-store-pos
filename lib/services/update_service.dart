import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
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
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      final buildNumber = info.buildNumber;
      print('[UPDATE] Current version: $currentVersion (build $buildNumber)');

      // Write debug to file so user can check
      final debugFile = File('${Directory.systemTemp.path}\\update_debug.log');
      await debugFile.writeAsString('=== Update Check ===\n'
          'Time: ${DateTime.now()}\n'
          'Current version: $currentVersion (build $buildNumber)\n');

      print('[UPDATE] Calling GitHub API: $_apiUrl');
      await debugFile.writeAsString(
          'API URL: $_apiUrl\n',
          mode: FileMode.append);

      final response = await http.get(Uri.parse(_apiUrl)).timeout(const Duration(seconds: 15));
      print('[UPDATE] API response status: ${response.statusCode}');
      await debugFile.writeAsString(
          'Response status: ${response.statusCode}\n',
          mode: FileMode.append);

      if (response.statusCode != 200) {
        await debugFile.writeAsString(
            'Response body: ${response.body}\n',
            mode: FileMode.append);
        return null;
      }

      final release = json.decode(response.body);
      final tagName = release['tag_name'] ?? '';
      final latestVersion = tagName.replaceFirst('v', '');
      print('[UPDATE] Latest version from GitHub: $latestVersion');

      await debugFile.writeAsString(
          'Tag name: $tagName\n'
          'Latest version: $latestVersion\n'
          'Release body: ${release['body']}\n',
          mode: FileMode.append);

      if (latestVersion.isEmpty) {
        await debugFile.writeAsString('Result: empty latest version\n', mode: FileMode.append);
        return null;
      }
      if (latestVersion == currentVersion) {
        print('[UPDATE] Versions match - no update needed');
        await debugFile.writeAsString('Result: versions match\n', mode: FileMode.append);
        return null;
      }

      // Check if this version was skipped
      final skippedVersion = await getSkippedVersion();
      if (skippedVersion == latestVersion) {
        print('[UPDATE] Version $latestVersion was skipped by user');
        await debugFile.writeAsString('Result: version skipped\n', mode: FileMode.append);
        return null;
      }

      final assets = (release['assets'] as List?) ?? [];
      print('[UPDATE] Assets count: ${assets.length}');
      await debugFile.writeAsString('Assets: ${assets.length}\n', mode: FileMode.append);
      for (final a in assets) {
        final name = a['name'] ?? 'unknown';
        final size = a['size'] ?? 0;
        print('[UPDATE]   - $name ($size bytes)');
        await debugFile.writeAsString('  - $name ($size bytes)\n', mode: FileMode.append);
      }
      final zipAsset = assets.where((a) => (a['name'] ?? '').toString().endsWith('.zip')).toList();
      if (zipAsset.isEmpty) {
        print('[UPDATE] No zip asset found');
        await debugFile.writeAsString('Result: no zip asset\n', mode: FileMode.append);
        return null;
      }

      final downloadUrl = zipAsset.first['browser_download_url'] ?? '';
      print('[UPDATE] Download URL: $downloadUrl');
      await debugFile.writeAsString(
          'Result: UPDATE AVAILABLE\n'
          'Download URL: $downloadUrl\n',
          mode: FileMode.append);

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: release['body'] ?? '',
      );
    } catch (e, stackTrace) {
      print('[UPDATE] Check failed: $e');
      try {
        final debugFile = File('${Directory.systemTemp.path}\\update_debug.log');
        await debugFile.writeAsString(
            'ERROR: $e\n'
            'Stack: $stackTrace\n',
            mode: FileMode.append);
      } catch (_) {}
      return null;
    }
  }

  /// Download and install update. Returns path to extracted folder.
  Future<String> downloadAndInstall(UpdateInfo update, {void Function(double progress)? onProgress}) async {
    final tempDir = await getTemporaryDirectory();
    final zipPath = '${tempDir.path}\\update.zip';
    final extractDir = '${tempDir.path}\\update_extract';

    // Download zip
    Logger.info('Downloading update: ${update.downloadUrl}');
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(update.downloadUrl));
    final response = await client.send(request).timeout(const Duration(minutes: 5));

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    final sink = File(zipPath).openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(receivedBytes / totalBytes);
      }
    }
    await sink.close();
    client.close();

    Logger.info('Download complete: $receivedBytes bytes');

    // Extract zip
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Clear extract directory
    final extractDirObj = Directory(extractDir);
    if (await extractDirObj.exists()) {
      await extractDirObj.delete(recursive: true);
    }
    await extractDirObj.create(recursive: true);

    // Extract files
    for (final file in archive) {
      final filePath = '$extractDir\\${file.name}';
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
    final batScript = '''
@echo off
title Ideal Store POS Updater
set "LOG=%TEMP%\\update_install.log"

:: Define paths using set (avoids Dart interpolation issues)
set "SOURCE=$sourceDir"
set "DEST=$appDir"
set "EXE=$exeName"

echo [%date% %time%] ====== UPDATE STARTED ======>> "%LOG%"
echo [%date% %time%] Source: %%SOURCE%% >> "%LOG%"
echo [%date% %time%] Dest: %%DEST%% >> "%LOG%"

:: Validate paths exist
if not exist "%%SOURCE%%" (
    echo [%date% %time%] ERROR: Source path does not exist >> "%LOG%"
    goto :ERROR
)
if not exist "%%DEST%%" (
    echo [%date% %time%] ERROR: Dest path does not exist >> "%LOG%"
    goto :ERROR
)

:: Wait for app to fully close
echo [%date% %time%] Waiting 5s for app to close... >> "%LOG%"
timeout /t 5 /nobreak >nul

:: Force kill any remaining instance
echo [%date% %time%] Killing old process... >> "%LOG%"
taskkill /f /im "%%EXE%%" >nul 2>&1
timeout /t 2 /nobreak >nul

:: Kill again in case it lingered
taskkill /f /im "%%EXE%%" >nul 2>&1

:: Remove old files
echo [%date% %time%] Deleting old files... >> "%LOG%"
del /Q "%%DEST%%\\*.dll" 2>>"%LOG%"
del /Q "%%DEST%%\\*.exe" 2>>"%LOG%"
del /Q "%%DEST%%\\*.dat" 2>>"%LOG%"
del /Q "%%DEST%%\\*.json" 2>>"%LOG%"
timeout /t 1 /nobreak >nul

:: Copy new files
echo [%date% %time%] Copying new files... >> "%LOG%"
xcopy /E /Y /I "%%SOURCE%%" "%%DEST%%" >> "%LOG%" 2>&1
if errorlevel 1 (
    echo [%date% %time%] ERROR: xcopy failed with errorlevel %%errorlevel%% >> "%LOG%"
    goto :ERROR
)

:: Verify exe exists after copy
if not exist "%%DEST%%\\%%EXE%%" (
    echo [%date% %time%] ERROR: exe not found after copy >> "%LOG%"
    goto :ERROR
)

echo [%date% %time%] Update successful, restarting app... >> "%LOG%"
start "" "%%DEST%%\\%%EXE%%"
goto :DONE

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

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
  });
}
