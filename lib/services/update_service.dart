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
      print('[UPDATE] Current version: $currentVersion');

      final response = await http.get(Uri.parse(_apiUrl)).timeout(const Duration(seconds: 10));
      print('[UPDATE] API response status: ${response.statusCode}');
      if (response.statusCode != 200) return null;

      final release = json.decode(response.body);
      final tagName = release['tag_name'] ?? '';
      final latestVersion = tagName.replaceFirst('v', '');
      print('[UPDATE] Latest version from GitHub: $latestVersion');

      if (latestVersion.isEmpty) return null;
      if (latestVersion == currentVersion) {
        print('[UPDATE] Versions match - no update needed');
        return null;
      }

      final assets = (release['assets'] as List?) ?? [];
      print('[UPDATE] Assets count: ${assets.length}');
      for (final a in assets) {
        print('[UPDATE]   - ${a["name"]} (${a["size"]} bytes)');
      }
      final zipAsset = assets.where((a) => (a['name'] ?? '').toString().endsWith('.zip')).toList();
      if (zipAsset.isEmpty) {
        print('[UPDATE] No zip asset found');
        return null;
      }

      print('[UPDATE] Update available: $currentVersion → $latestVersion');
      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: zipAsset.first['browser_download_url'],
        releaseNotes: release['body'] ?? '',
      );
    } catch (e) {
      print('[UPDATE] Check failed: $e');
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
