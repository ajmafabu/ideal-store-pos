import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  final pngFile = File('assets/app_icon.png');
  if (!await pngFile.exists()) {
    print('ERROR: assets/app_icon.png not found');
    exit(1);
  }

  final pngBytes = await pngFile.readAsBytes();
  print('Read PNG: ${pngBytes.length} bytes');

  // ICO format: we embed the PNG directly (Windows supports PNG-in-ICO)
  // ICO header: 6 bytes
  // ICO directory entry: 16 bytes per image
  // We'll create 4 sizes: 16, 32, 48, 256

  final images = [16, 32, 48, 256];
  final headerSize = 6;
  final entrySize = 16;
  final directorySize = entrySize * images.length;

  // Calculate offsets
  final offsets = <int>[];
  var offset = headerSize + directorySize;
  for (final size in images) {
    offsets.add(offset);
    offset += pngBytes.length;
  }

  // Write ICO
  final ico = BytesBuilder();

  // ICO header
  ico.addByte(0); // reserved
  ico.addByte(0);
  ico.addByte(1); ico.addByte(0); // type: 1 = icon
  ico.addByte(images.length); ico.addByte(0); // image count

  // Directory entries
  for (var i = 0; i < images.length; i++) {
    final size = images[i];
    ico.addByte(size > 255 ? 0 : size); // width
    ico.addByte(size > 255 ? 0 : size); // height
    ico.addByte(0);  // color palette
    ico.addByte(0);  // reserved
    ico.addByte(1); ico.addByte(0); // color planes
    ico.addByte(32); ico.addByte(0); // bits per pixel
    // size of image data
    final dataSize = pngBytes.length;
    ico.addByte(dataSize & 0xFF);
    ico.addByte((dataSize >> 8) & 0xFF);
    ico.addByte((dataSize >> 16) & 0xFF);
    ico.addByte((dataSize >> 24) & 0xFF);
    // offset
    final off = offsets[i];
    ico.addByte(off & 0xFF);
    ico.addByte((off >> 8) & 0xFF);
    ico.addByte((off >> 16) & 0xFF);
    ico.addByte((off >> 24) & 0xFF);
  }

  // Image data (same PNG for all sizes - Windows will scale)
  for (final _ in images) {
    ico.add(pngBytes);
  }

  final icoFile = File('windows/runner/resources/app_icon.ico');
  await icoFile.writeAsBytes(ico.toBytes());
  print('Created: ${icoFile.path} (${ico.toBytes().length} bytes)');
}
