import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import '../utils/tamil_bitmap_renderer.dart';
import '../utils/thermal_invoice.dart';

class ThermalPrinterService {
  static const String _savedDeviceKey = 'saved_printer_address';
  static const String _savedDeviceNameKey = 'saved_printer_name';
  static const String _savedWindowsPrinterKey = 'saved_windows_printer_name';
  static const String _autoPrintKey = 'auto_print_enabled';

  static final Uint8List _init = Uint8List.fromList([0x1B, 0x40]);
  static final Uint8List _boldOn = Uint8List.fromList([0x1B, 0x45, 0x01]);
  static final Uint8List _boldOff = Uint8List.fromList([0x1B, 0x45, 0x00]);
  static final Uint8List _centerAlign = Uint8List.fromList([0x1B, 0x61, 0x01]);
  static final Uint8List _leftAlign = Uint8List.fromList([0x1B, 0x61, 0x00]);
  static final Uint8List _feedAndCut = Uint8List.fromList([0x1D, 0x56, 0x00]);
  static final Uint8List _lineFeed = Uint8List.fromList([0x0A]);
  static const int _lineWidth = 48;

  Future<String?> getSavedPrinterAddress() async =>
      (await SharedPreferences.getInstance()).getString(_savedDeviceKey);
  Future<String?> getSavedPrinterName() async =>
      (await SharedPreferences.getInstance()).getString(_savedDeviceNameKey);

  Future<void> savePrinter(String address, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedDeviceKey, address);
    await prefs.setString(_savedDeviceNameKey, name);
  }

  Future<void> clearPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedDeviceKey);
    await prefs.remove(_savedDeviceNameKey);
  }

  Future<String?> getSavedWindowsPrinter() async =>
      (await SharedPreferences.getInstance()).getString(
        _savedWindowsPrinterKey,
      );

  Future<bool> getAutoPrint() async =>
      (await SharedPreferences.getInstance()).getBool(_autoPrintKey) ?? false;

  Future<void> setAutoPrint(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPrintKey, enabled);
  }

  Future<BluetoothDevice?> selectDevice(BuildContext context) =>
      FlutterBluetoothPrinter.selectDevice(context);

  Future<bool> printText(String text, {bool hasTamil = false}) async {
    try {
      final address = await getSavedPrinterAddress();
      if (address == null || address.isEmpty) return false;

      for (int i = 0; i < 3; i++) {
        try {
          await FlutterBluetoothPrinter.connect(address);
          break;
        } catch (e) {
          if (i == 2) rethrow;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      await Future.delayed(const Duration(milliseconds: 300));

      // Use image printing for ALL text (Tamil or English)
      return await _bluetoothPrintImage(text, address);
    } catch (e) {
      Logger.error('printText', e);
      return false;
    }
  }

  /// Image-based printing - renders all text as bitmap for perfect output
  Future<bool> _bluetoothPrintImage(String text, String address) async {
    try {
      final buffer = BytesBuilder();
      buffer.add(_init);
      await Future.delayed(const Duration(milliseconds: 100));

      for (final line in text.split('\n')) {
        final trimmed = line.trim();

        if (trimmed.isEmpty) {
          // Empty line - just line feed
          buffer.add(_lineFeed);
          continue;
        }

        // Determine if this line should be bold
        final isBold =
            trimmed == 'Ideal store' ||
            trimmed == 'QUOTATION' ||
            trimmed.startsWith('TOTAL:') ||
            trimmed.startsWith('PAID') ||
            trimmed.startsWith('BILL NO:') ||
            trimmed.startsWith('DATE:') ||
            trimmed.startsWith('Customer:');

        // Render as bitmap image
        final bitmap = await TamilBitmapRenderer.renderToBitmap(
          line,
          fontSize: isBold ? 36 : 30,
          bold: isBold,
        );

        if (bitmap.isNotEmpty) {
          buffer.add(_leftAlign);
          buffer.add(TamilBitmapRenderer.printBitmapCommand(bitmap));
        }
      }

      buffer.add(_lineFeed);
      buffer.add(_lineFeed);
      buffer.add(_feedAndCut);

      return await FlutterBluetoothPrinter.printBytes(
        address: address,
        data: buffer.toBytes(),
        keepConnected: true,
        delayTime: 150,
      );
    } catch (e) {
      Logger.error('_bluetoothPrintImage', e);
      return false;
    }
  }

  Future<bool> _bluetoothPrintTamil(String text, String address) async {
    // Tamil now uses same image printing as English
    return await _bluetoothPrintImage(text, address);
  }

  Future<bool> isConfigured() async => (await getSavedPrinterAddress()) != null;

  Future<bool> printViaWindowsDialog(
    String text, {
    String title = 'Invoice',
  }) async {
    try {
      return await _printReceipt(text, title: title);
    } catch (e) {
      Logger.error('printViaWindowsDialog', e);
      return false;
    }
  }

  Future<bool> printDirect(
    String text, {
    String title = 'Invoice',
    bool hasTamil = false,
  }) async {
    try {
      return await _printReceipt(text, title: title, hasTamil: hasTamil);
    } catch (e) {
      Logger.error('printDirect', e);
      return await printViaWindowsDialog(text, title: title);
    }
  }

  /// Legacy text-based print — converts text to structured data and prints.
  Future<bool> _printReceipt(
    String text, {
    String title = 'Invoice',
    bool hasTamil = false,
  }) async {
    try {
      final lines = text.split('\n');
      final receiptData = _textToReceiptData(lines);
      return await printStructured(receiptData, title: title);
    } catch (e) {
      Logger.error('_printReceipt', e);
      return false;
    }
  }

  /// Fallback: convert plain text lines to ThermalReceiptData for old callers.
  ThermalReceiptData _textToReceiptData(List<String> lines) {
    final header = <String>[];
    final rows = <ThermalRow>[];
    final totals = <String>[];
    final footer = <String>[];
    var section = 'header';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('S.No') || trimmed.startsWith('───')) {
        if (section == 'header') {
          header.add(line);
          section = 'table';
          continue;
        }
      }
      if (trimmed.startsWith('Total Qty') ||
          trimmed.startsWith('Sub Total') ||
          trimmed.startsWith('NET TOTAL') ||
          trimmed.startsWith('Discount') ||
          trimmed.startsWith('Extra') ||
          trimmed.startsWith('Round Off')) {
        section = 'totals';
      }
      if (trimmed.startsWith('Payment:') ||
          trimmed.startsWith('Amount Paid') ||
          trimmed.startsWith('Balance:') ||
          trimmed.startsWith('Items:') ||
          trimmed.startsWith('Thank') ||
          trimmed.startsWith('Visit')) {
        section = 'footer';
      }

      switch (section) {
        case 'header':
          header.add(line);
        case 'table':
          final match = RegExp(
            r'^(\d+)\s+(.+?)\s+(\d+)\s+(\d+\.?\d*)\s+(\d+\.?\d*)$',
          ).firstMatch(trimmed);
          if (match != null) {
            rows.add(
              ThermalRow(
                sNo: int.parse(match.group(1)!),
                productName: match.group(2)!,
                qty: int.parse(match.group(3)!),
                rate: double.parse(match.group(4)!),
                amount: double.parse(match.group(5)!),
              ),
            );
          } else if (trimmed.isNotEmpty && !trimmed.startsWith('───')) {
            header.add(line);
          }
        case 'totals':
          totals.add(line);
        case 'footer':
          footer.add(line);
      }
    }

    return ThermalReceiptData(
      headerLines: header,
      rows: rows,
      totalLines: totals,
      footerLines: footer,
    );
  }

  /// Renders structured receipt data as image and prints.
  /// If autoPrint is enabled and a printer is saved, prints directly.
  /// Otherwise opens the Windows print dialog.
  /// Splits long receipts into multiple pages to avoid printer truncation.
  Future<bool> printStructured(
    ThermalReceiptData data, {
    String title = 'Quotation',
    bool forceDialog = false,
  }) async {
    try {
      final pngBytes = await TamilBitmapRenderer.renderReceiptAsImage(
        headerLines: data.headerLines,
        rows: data.rows,
        totalLines: data.totalLines,
        footerLines: data.footerLines,
      );

      if (pngBytes.isEmpty) return false;

      final tempImage = await decodeImageFromList(pngBytes);
      final iw = tempImage.width;
      final ih = tempImage.height;
      tempImage.dispose();

      if (iw <= 0 || ih <= 0) return false;

      final pdf = pw.Document();
      final imageWidthMm = iw * 25.4 / 203;
      final imageHeightMm = ih * 25.4 / 203;

      // Split into pages if too tall (thermal printer limit ~297mm = A4)
      const maxPageHeightMm = 297.0;
      if (imageHeightMm <= maxPageHeightMm) {
        final pageFormat = PdfPageFormat(
          PdfPageFormat.mm * imageWidthMm,
          PdfPageFormat.mm * imageHeightMm,
          marginBottom: 0,
          marginTop: 0,
          marginLeft: 0,
          marginRight: 0,
        );
        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (context) => pw.Image(pw.MemoryImage(pngBytes)),
          ),
        );
      } else {
        // Split image into vertical chunks
        final totalChunks = (imageHeightMm / maxPageHeightMm).ceil();
        final chunkHeightPx = ih ~/ totalChunks;

        for (int i = 0; i < totalChunks; i++) {
          final startY = i * chunkHeightPx;
          final chunkH = (i == totalChunks - 1) ? ih - startY : chunkHeightPx;
          final chunkHMm = chunkH * 25.4 / 203;

          // Crop the chunk from the full image
          final chunkBytes = await _cropImagePng(
            pngBytes,
            iw,
            ih,
            0,
            startY,
            iw,
            chunkH,
          );

          if (chunkBytes.isEmpty) continue;

          final pageFormat = PdfPageFormat(
            PdfPageFormat.mm * imageWidthMm,
            PdfPageFormat.mm * chunkHMm,
            marginBottom: 0,
            marginTop: 0,
            marginLeft: 0,
            marginRight: 0,
          );

          pdf.addPage(
            pw.Page(
              pageFormat: pageFormat,
              build: (context) => pw.Image(pw.MemoryImage(chunkBytes)),
            ),
          );
        }
      }

      // Try direct printing if auto-print is enabled and printer is saved
      if (!forceDialog) {
        final autoPrint = await getAutoPrint();
        final savedPrinterName = await getSavedWindowsPrinter();

        if (autoPrint &&
            savedPrinterName != null &&
            savedPrinterName.isNotEmpty) {
          final printers = await Printing.listPrinters();
          final savedPrinter = printers.cast<Printer?>().firstWhere(
            (p) => p?.name == savedPrinterName,
            orElse: () => null,
          );

          if (savedPrinter != null) {
            try {
              await Printing.directPrintPdf(
                printer: savedPrinter,
                onLayout: (format) => pdf.save(),
                name: title,
              );
              return true;
            } catch (e) {
              Logger.error('directPrint failed, falling back to dialog', e);
              // Fall through to dialog
            }
          }
        }
      }

      // Fallback: open print dialog
      await Printing.layoutPdf(onLayout: (format) => pdf.save(), name: title);
      return true;
    } catch (e) {
      Logger.error('printStructured', e);
      return false;
    }
  }

  /// Crops a PNG image and returns new PNG bytes
  Future<Uint8List> _cropImagePng(
    Uint8List srcPng,
    int srcW,
    int srcH,
    int left,
    int top,
    int width,
    int height,
  ) async {
    try {
      final image = await decodeImageFromList(srcPng);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          left.toDouble(),
          top.toDouble(),
          width.toDouble(),
          height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint(),
      );
      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(width, height);
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      croppedImage.dispose();
      return byteData?.buffer.asUint8List() ?? Uint8List(0);
    } catch (e) {
      Logger.error('_cropImagePng', e);
      return Uint8List(0);
    }
  }

  /// Fallback: render all lines as simple bitmap (no column layout)
  Future<bool> _printFallbackText(ThermalReceiptData data, String title) async {
    try {
      // Pass structured data directly to get fixed column positions
      final pngBytes = await TamilBitmapRenderer.renderReceiptAsImage(
        headerLines: data.headerLines,
        rows: data.rows,
        totalLines: data.totalLines,
        footerLines: data.footerLines,
        fontSize: 24,
      );

      if (pngBytes.isEmpty) {
        Logger.error('PS: Fallback bitmap empty');
        return false;
      }

      final tempImage = await decodeImageFromList(pngBytes);
      final iw = tempImage.width;
      final ih = tempImage.height;
      tempImage.dispose();

      if (iw <= 0 || ih <= 0) return false;

      final pdf = pw.Document();
      final imageWidthMm = iw * 25.4 / ThermalColumnLayout.dpi;
      final imageHeightMm = ih * 25.4 / ThermalColumnLayout.dpi;
      final pageFormat = PdfPageFormat(
        PdfPageFormat.mm * imageWidthMm,
        PdfPageFormat.mm * imageHeightMm,
        marginBottom: 0,
        marginTop: 0,
        marginLeft: 0,
        marginRight: 0,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (context) => pw.Image(pw.MemoryImage(pngBytes)),
        ),
      );

      Logger.info('PS: Fallback bitmap printing...');
      await Printing.layoutPdf(onLayout: (format) => pdf.save(), name: title);
      Logger.info('PS: Fallback done');
      return true;
    } catch (e) {
      Logger.error('PS: Fallback bitmap failed: $e');
      return false;
    }
  }

  String _fmtP(double v) => v.toStringAsFixed(2);

  /// Formats receipt data as Courier-compatible ASCII text with fixed-width columns.
  String _formatForCourier(ThermalReceiptData data) {
    final sb = StringBuffer();
    final sep = '-' * _lineWidth;

    // Header
    for (final line in data.headerLines) {
      if (line.startsWith('\u2500')) {
        sb.writeln(sep);
      } else {
        sb.writeln(line);
      }
    }

    // Table header
    sb.writeln(
      '${"S.No".padRight(4)} ${"Item Name".padRight(19)} '
      '${"Qty".padRight(5)} ${"Price".padRight(8)} ${"Total".padRight(8)}',
    );
    sb.writeln(sep);

    // Table rows
    for (final row in data.rows) {
      final sno = row.sNo.toString().padLeft(4);
      final name = row.productName.length > 19
          ? row.productName.substring(0, 19)
          : row.productName.padRight(19);
      final qty = row.qty.toString().padLeft(5);
      final price = row.rate.toStringAsFixed(2).padLeft(8);
      final total = row.amount.toStringAsFixed(2).padLeft(8);
      sb.writeln('$sno $name $qty $price $total');
    }

    sb.writeln(sep);

    // Totals
    for (final line in data.totalLines) {
      if (line.startsWith('\u2500')) {
        sb.writeln(sep);
      } else {
        final match = RegExp(r'^(.+?):\s*(.+)$').firstMatch(line);
        if (match != null) {
          final label = match.group(1)!.trim();
          final value = match.group(2)!.trim();
          sb.writeln('${label.padRight(22)}: ${value.padLeft(10)}');
        } else {
          sb.writeln(line);
        }
      }
    }

    // Footer
    for (final line in data.footerLines) {
      if (line.startsWith('\u2500')) {
        sb.writeln(sep);
      } else {
        sb.writeln(line);
      }
    }

    return sb.toString();
  }

  Future<List<Printer>> getAvailablePrinters() async {
    try {
      return await Printing.listPrinters();
    } catch (e) {
      Logger.error('getAvailablePrinters', e);
      return [];
    }
  }

  Future<Printer?> selectPrinter(BuildContext context) async {
    try {
      final printers = await getAvailablePrinters();
      if (printers.isEmpty) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No printers found'),
              backgroundColor: Colors.orange,
            ),
          );
        return null;
      }
      final selected = await showDialog<Printer>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select Printer'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: ListView.builder(
              itemCount: printers.length,
              itemBuilder: (_, i) {
                final p = printers[i];
                final isTvs =
                    p.name.toLowerCase().contains('tvs') ||
                    p.name.toLowerCase().contains('rp3200');
                return ListTile(
                  leading: Icon(
                    isTvs ? Icons.print : Icons.print_outlined,
                    color: isTvs ? Colors.green : Colors.grey,
                  ),
                  title: Text(p.name),
                  subtitle: Text(isTvs ? 'TVS Thermal Printer' : ''),
                  trailing: isTvs
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () => Navigator.pop(ctx, p),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (selected != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_savedWindowsPrinterKey, selected.name);
      }
      return selected;
    } catch (e) {
      Logger.error('selectPrinter', e);
      return null;
    }
  }

  Future<void> shareAsTextFile(
    String text, {
    String fileName = 'invoice',
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName.txt');
      await file.writeAsString(text);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Invoice',
        subject: '$fileName.txt',
      );
    } catch (e) {
      Logger.error('shareAsTextFile', e);
    }
  }
}
