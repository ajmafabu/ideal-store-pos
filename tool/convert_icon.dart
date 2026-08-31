import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

void main() async {
  final file = File('assets/app_icon.png');
  if (!await file.exists()) {
    print('ERROR: assets/app_icon.png not found');
    exit(1);
  }

  final bytes = await file.readAsBytes();
  print('File: ${bytes.length} bytes, header: ${bytes.sublist(0, 4)}');

  // Decode as JPEG (the file is actually JPEG despite .png extension)
  final image = img.decodeJpg(bytes) ?? img.decodePng(bytes);
  if (image == null) {
    print('ERROR: Failed to decode image');
    exit(1);
  }

  print('Decoded: ${image.width}x${image.height}');

  // Build ICO with multiple sizes
  final sizes = [16, 32, 48, 64, 128, 256];
  final pngDataList = <Uint8List>[];

  for (final size in sizes) {
    final resized = img.copyResize(image, width: size, height: size, interpolation: img.Interpolation.linear);
    final pngData = img.encodePng(resized);
    pngDataList.add(pngData);
    print('  ${size}x${size}: ${pngData.length} bytes');
  }

  // Build ICO file
  final ico = BytesBuilder();
  final numImages = sizes.length;

  // ICO header (6 bytes)
  ico.add([0, 0]); // reserved
  ico.add([1, 0]); // type: 1 = icon
  ico.addByte(numImages & 0xFF);
  ico.addByte(0);

  // Calculate data offset
  var dataOffset = 6 + (numImages * 16);

  // Directory entries
  for (var i = 0; i < numImages; i++) {
    final size = sizes[i];
    final pngData = pngDataList[i];

    ico.addByte(size > 255 ? 0 : size); // width
    ico.addByte(size > 255 ? 0 : size); // height
    ico.addByte(0); // color palette
    ico.addByte(0); // reserved
    ico.addByte(1); ico.addByte(0); // color planes
    ico.addByte(32); ico.addByte(0); // bits per pixel

    // image data size (little-endian)
    ico.addByte(pngData.length & 0xFF);
    ico.addByte((pngData.length >> 8) & 0xFF);
    ico.addByte((pngData.length >> 16) & 0xFF);
    ico.addByte((pngData.length >> 24) & 0xFF);

    // offset (little-endian)
    ico.addByte(dataOffset & 0xFF);
    ico.addByte((dataOffset >> 8) & 0xFF);
    ico.addByte((dataOffset >> 16) & 0xFF);
    ico.addByte((dataOffset >> 24) & 0xFF);

    dataOffset += pngData.length;
  }

  // Image data
  for (final pngData in pngDataList) {
    ico.add(pngData);
  }

  final icoFile = File('windows/runner/resources/app_icon.ico');
  await icoFile.writeAsBytes(ico.toBytes());
  print('Saved: ${icoFile.path} (${ico.toBytes().length} bytes)');
}
