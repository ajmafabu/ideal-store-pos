import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

class UpdateService {
  static const _repo = 'ajmafabu/ideal-store-pos';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';

  /// Check GitHub for a newer version. Returns null if up-to-date.
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
    final appDir = Directory(Platform.resolvedExecutable).parent.parent.path;
    final exeName = Platform.resolvedExecutable.split('\\').last;

    Logger.info('Installing update to: $appDir');

    // Create a batch script that:
    // 1. Waits for the app to close
    // 2. Copies new files over old ones
    // 3. Restarts the app
    // 4. Cleans up
    final batScript = '''
@echo off
timeout /t 2 /nobreak >nul
xcopy /E /Y /I "$extractDir" "$appDir"
start "" "$appDir\\$exeName"
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
