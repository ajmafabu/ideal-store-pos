import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ThermalColumnLayout {
  ThermalColumnLayout._();
  static const double printableWidthPx = 624;
  static const double dpi = 203;
}

class ThermalRow {
  final int sNo;
  final String productName;
  final int qty;
  final double rate;
  final double amount;

  const ThermalRow({
    required this.sNo,
    required this.productName,
    required this.qty,
    required this.rate,
    required this.amount,
  });
}

class TamilBitmapRenderer {
  static const double _snoX = 0;
  static const double _snoW = 24;
  static const double _partX = 24;
  static const double _partW = 250;
  static const double _qtyX = 274;
  static const double _qtyW = 42;
  static const double _rateX = 316;
  static const double _rateW = 100;
  static const double _amtX = 416;
  static const double _amtW = 162;
  static const double _lineEnd = 578;
  static const double _borderH = 1.0;

  static Future<Uint8List> renderToBitmap(
    String text, {
    double fontSize = 32,
    double maxWidth = 576,
    bool bold = false,
  }) async {
    if (text.isEmpty) return Uint8List(0);

    final hasTamil = RegExp(r'[\u0B80-\u0BFF]').hasMatch(text);
    final fontFamily = hasTamil ? 'NotoSansTamil' : 'NotoSans';

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.black,
          fontFamily: fontFamily,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );

    textPainter.layout(maxWidth: maxWidth);
    final size = textPainter.size;
    canvas.drawColor(Colors.white, BlendMode.src);
    textPainter.paint(canvas, Offset.zero);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    if (byteData == null) return Uint8List(0);

    final rgba = byteData.buffer.asUint8List();
    final width = size.width.ceil();
    final height = size.height.ceil();
    final rowBytes = ((width + 7) ~/ 8);
    final bitmap = Uint8List(4 + rowBytes * height);

    bitmap[0] = width & 0xFF;
    bitmap[1] = (width >> 8) & 0xFF;
    bitmap[2] = height & 0xFF;
    bitmap[3] = (height >> 8) & 0xFF;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final rgbaIndex = (y * width + x) * 4;
        final brightness =
            (rgba[rgbaIndex] * 0.299 +
            rgba[rgbaIndex + 1] * 0.587 +
            rgba[rgbaIndex + 2] * 0.114);
        if (brightness < 128) {
          bitmap[4 + y * rowBytes + (x ~/ 8)] |= (1 << (7 - (x % 8)));
        }
      }
    }

    return bitmap;
  }

  static Future<Uint8List> renderReceiptAsImage({
    required List<String> headerLines,
    required List<ThermalRow> rows,
    required List<String> totalLines,
    required List<String> footerLines,
    double fontSize = 24,
  }) async {
    const cw = ThermalColumnLayout.printableWidthPx;
    const thinSep = 0.5;

    final List<_LineInfo> lineInfos = [];
    double totalH = 4;

    // ── HEADER ──
    for (int i = 0; i < headerLines.length; i++) {
      final line = headerLines[i];
      if (line.isEmpty) continue;

      final isFirst = i == 0;
      final isQuotation = line == 'QUOTATION';
      final isDate = line.startsWith('Date:');
      final isCustomer = line.startsWith('Customer:');

      if (isDate && line.contains('Time:')) {
        // Split date and time into left/right aligned
        final parts = line.split(RegExp(r'\s+Time:\s*'));
        final datePart = parts.isNotEmpty ? 'Date: ${parts[0].replaceFirst('Date: ', '')}' : line;
        final timePart = parts.length > 1 ? 'Time: ${parts[1]}' : '';

        final dateTp = _makeTp(datePart, 16, false);
        final timeTp = _makeTp(timePart, 16, false);
        dateTp.layout(maxWidth: cw / 2);
        timeTp.layout(maxWidth: cw / 2);
        final rowH = [dateTp.height, timeTp.height].reduce((a, b) => a > b ? a : b);
        lineInfos.add(_LineInfo(
          type: _LineType.dateRow,
          height: rowH + 4,
          painter: dateTp,
          painter2: timeTp,
        ));
        totalH += rowH + 4;
      } else {
        final sz = isFirst ? 28.0 : (isQuotation ? 22.0 : (isCustomer ? 18.0 : 18.0));
        final bld = isFirst || isQuotation || isCustomer;
        final tp = _makeTp(line, sz, bld);
        tp.layout(maxWidth: cw);
        lineInfos.add(_LineInfo(
          type: _LineType.centered,
          height: tp.height + 3,
          painter: tp,
        ));
        totalH += tp.height + 3;
      }

      // Add thin separator after shop name and after QUOTATION
      if (isFirst || isQuotation) {
        lineInfos.add(_LineInfo(type: _LineType.thinSep, height: thinSep));
        totalH += thinSep;
      }
    }

    // ── TABLE HEADER ──
    lineInfos.add(_LineInfo(type: _LineType.thickSep, height: 1.0));
    totalH += 1.0;

    final hdrSno = _makeTp('#', 16, true);
    final hdrPart = _makeTp('Item', 16, true);
    final hdrQty = _makeTp('Qty', 16, true);
    final hdrRate = _makeTp('Rate', 16, true);
    final hdrAmt = _makeTp('Amt', 16, true);
    hdrSno.layout(maxWidth: _snoW);
    hdrPart.layout(maxWidth: _partW);
    hdrQty.layout(maxWidth: _qtyW);
    hdrRate.layout(maxWidth: _rateW);
    hdrAmt.layout(maxWidth: _amtW);
    final hdrH = hdrSno.height + 6;
    lineInfos.add(_LineInfo(
      type: _LineType.tableRow,
      height: hdrH,
      painters: [hdrSno, hdrPart, hdrQty, hdrRate, hdrAmt],
    ));
    totalH += hdrH;

    lineInfos.add(_LineInfo(type: _LineType.thickSep, height: 1.0));
    totalH += 1.0;

    // ── DATA ROWS ──
    for (final row in rows) {
      final sno = _makeTp('${row.sNo}', 18, false);
      var productName = row.productName;

      // Pixel-based truncation
      final partTp = _makeTp(productName, 18, false);
      partTp.layout(maxWidth: _partW - 8);
      if (partTp.width > _partW - 8) {
        int maxChars = productName.length;
        while (maxChars > 3) {
          final test = '${productName.substring(0, maxChars)}…';
          final testTp = _makeTp(test, 18, false);
          testTp.layout(maxWidth: _partW - 8);
          if (testTp.width <= _partW - 8) {
            productName = test;
            break;
          }
          maxChars--;
        }
        if (maxChars <= 3) productName = '${productName.substring(0, 3)}…';
      }

      final part = _makeTp(productName, 18, false);
      final qty = _makeTp('${row.qty}', 18, false);
      final rate = _makeTp(row.rate.toStringAsFixed(2), 18, false);
      final amt = _makeTp(row.amount.toStringAsFixed(2), 18, true);
      sno.layout(maxWidth: _snoW);
      part.layout(maxWidth: _partW - 8);
      qty.layout(maxWidth: _qtyW);
      rate.layout(maxWidth: _rateW);
      amt.layout(maxWidth: _amtW);

      final h = [sno, part, qty, rate, amt]
          .fold<double>(0, (prev, tp) => tp.height > prev ? tp.height : prev);
      lineInfos.add(_LineInfo(
        type: _LineType.tableRow,
        height: h + 6,
        painters: [sno, part, qty, rate, amt],
      ));
      totalH += h + 6;

      // Thin separator between rows
      lineInfos.add(_LineInfo(type: _LineType.thinSep, height: thinSep));
      totalH += thinSep;
    }

    // ── TOTALS ──
    lineInfos.add(_LineInfo(type: _LineType.thickSep, height: 1.0));
    totalH += 1.0;

    for (final line in totalLines) {
      final isNetTotal = line.startsWith('NET TOTAL');
      final isTotalItems = line.startsWith('Total Items') || line.startsWith('Items:');

      if (isNetTotal) {
        // Split "NET TOTAL: 1320.00" into label and amount
        final colonIdx = line.indexOf(':');
        if (colonIdx > 0) {
          final label = line.substring(0, colonIdx).trim();
          final amount = line.substring(colonIdx + 1).trim();
          final labelTp = _makeTp(label, 22, true);
          final amtTp = _makeTp(amount, 26, true);
          labelTp.layout(maxWidth: 300);
          amtTp.layout(maxWidth: 200);
          final rowH = [labelTp.height, amtTp.height].reduce((a, b) => a > b ? a : b);
          lineInfos.add(_LineInfo(
            type: _LineType.netTotalRow,
            height: rowH + 6,
            painter: labelTp,
            painter2: amtTp,
          ));
          totalH += rowH + 6;
        } else {
          final tp = _makeTp(line, 24, true);
          tp.layout(maxWidth: cw);
          lineInfos.add(_LineInfo(
            type: _LineType.centered,
            height: tp.height + 4,
            painter: tp,
          ));
          totalH += tp.height + 4;
        }
      } else {
        final tp = _makeTp(line, 16, false);
        tp.layout(maxWidth: cw);
        lineInfos.add(_LineInfo(
          type: _LineType.leftAligned,
          height: tp.height + 3,
          painter: tp,
        ));
        totalH += tp.height + 3;
      }
    }

    lineInfos.add(_LineInfo(type: _LineType.thickSep, height: 1.0));
    totalH += 1.0;

    // ── FOOTER ──
    for (final line in footerLines) {
      if (line.isEmpty) continue;
      final tp = _makeTp(line, 15, false);
      tp.layout(maxWidth: cw);
      lineInfos.add(_LineInfo(
        type: _LineType.centered,
        height: tp.height + 3,
        painter: tp,
      ));
      totalH += tp.height + 3;
    }

    totalH += 4;

    final width = cw.toInt();
    final height = totalH.ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.drawColor(Colors.white, BlendMode.src);

    final thinPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 0.5;
    final thickPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0;

    double y = 4;
    for (final li in lineInfos) {
      switch (li.type) {
        case _LineType.empty:
          y += li.height;
        case _LineType.thinSep:
          canvas.drawLine(Offset(20, y), Offset(_lineEnd - 20, y), thinPaint);
          y += li.height;
        case _LineType.thickSep:
          canvas.drawLine(Offset(0, y), Offset(_lineEnd, y), thickPaint);
          y += li.height;
        case _LineType.centered:
          if (li.painter != null) {
            final cx = (width - li.painter!.width) / 2;
            li.painter!.paint(canvas, Offset(cx > 0 ? cx : 0, y));
          }
          y += li.height;
        case _LineType.leftAligned:
          if (li.painter != null) {
            li.painter!.paint(canvas, Offset(0, y));
          }
          y += li.height;
        case _LineType.rightAligned:
          if (li.painter != null) {
            final rx = width - li.painter!.width;
            li.painter!.paint(canvas, Offset(rx > 0 ? rx : 0, y));
          }
          y += li.height;
        case _LineType.dateRow:
          // Date left, Time right
          if (li.painter != null) {
            li.painter!.paint(canvas, Offset(0, y));
          }
          if (li.painter2 != null) {
            final timeRx = width - li.painter2!.width;
            li.painter2!.paint(canvas, Offset(timeRx > 0 ? timeRx : 0, y));
          }
          y += li.height;
        case _LineType.netTotalRow:
          // "NET TOTAL" left, amount right
          if (li.painter != null) {
            li.painter!.paint(canvas, Offset(0, y + 2));
          }
          if (li.painter2 != null) {
            final amtRx = width - li.painter2!.width;
            li.painter2!.paint(canvas, Offset(amtRx > 0 ? amtRx : 0, y));
          }
          y += li.height;
        case _LineType.tableRow:
          if (li.painters != null && li.painters!.length >= 5) {
            for (int i = 0; i < 5; i++) {
              final tp = li.painters![i];
              final cellY = y + (li.height - tp.height) / 2;
              double cellX;
              if (i == 0) {
                // S.No - center
                cellX = _snoX + (_snoW - tp.width) / 2;
              } else if (i == 1) {
                // Particulars - left +4px
                cellX = _partX + 4;
              } else {
                // Qty, Rate, Amount - right -4px
                final colX = i == 2 ? _qtyX : (i == 3 ? _rateX : _amtX);
                final colW = i == 2 ? _qtyW : (i == 3 ? _rateW : _amtW);
                cellX = colX + colW - tp.width - 4;
              }
              tp.paint(canvas, Offset(cellX, cellY));
            }
          }
          y += li.height;
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  }

  static TextPainter _makeTp(String text, double fontSize, bool bold) {
    final hasTamil = RegExp(r'[\u0B80-\u0BFF]').hasMatch(text);
    final fontFamily = hasTamil ? 'NotoSansTamil' : 'NotoSans';

    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.black,
          fontFamily: fontFamily,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    );
  }

  static Uint8List printBitmapCommand(Uint8List bitmap) {
    if (bitmap.isEmpty) return Uint8List(0);
    final buffer = BytesBuilder();
    buffer.add([0x1D, 0x76, 0x30]);
    buffer.add(bitmap);
    buffer.add([0x0A]);
    return buffer.toBytes();
  }

  static String getDisplayName(
    String? englishName,
    String? tamilName,
    bool useTamil,
  ) {
    if (useTamil && tamilName != null && tamilName.isNotEmpty) return tamilName;
    return englishName ?? '';
  }
}

enum _LineType {
  empty,
  thinSep,
  thickSep,
  centered,
  leftAligned,
  rightAligned,
  dateRow,
  netTotalRow,
  tableRow,
}

class _LineInfo {
  final _LineType type;
  final double height;
  final TextPainter? painter;
  final TextPainter? painter2;
  final List<TextPainter>? painters;

  _LineInfo({
    required this.type,
    required this.height,
    this.painter,
    this.painter2,
    this.painters,
  });
}
