import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ThermalColumnLayout {
  ThermalColumnLayout._();
  // 78mm thermal printer at 203 DPI: ~624px printable width
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
  // 5-column layout for 78mm printer (624px width)
  static const double _snoX = 0;
  static const double _snoW = 30;
  static const double _partX = 32;
  static const double _partW = 280;
  static const double _qtyX = 314;
  static const double _qtyW = 50;
  static const double _rateX = 366;
  static const double _rateW = 100;
  static const double _amtX = 468;
  static const double _amtW = 110;

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

  /// Renders receipt as PNG with FIXED pixel column positions.
  /// Supports Tamil via NotoSansTamil font on Flutter canvas.
  static Future<Uint8List> renderReceiptAsImage({
    required List<String> headerLines,
    required List<ThermalRow> rows,
    required List<String> totalLines,
    required List<String> footerLines,
    double fontSize = 24,
  }) async {
    const cw = ThermalColumnLayout.printableWidthPx;
    const lineGap = 4.0;
    const sepH = 3.0;

    // Phase 1: measure everything
    final List<_LineInfo> lineInfos = [];
    double totalH = 5; // reduced top padding

    for (final line in headerLines) {
      if (line.isEmpty) {
        lineInfos.add(_LineInfo(type: _LineType.empty, height: 8));
        totalH += 8;
        continue;
      }
      if (line.startsWith('\u2500') || line.startsWith('-')) {
        lineInfos.add(_LineInfo(type: _LineType.sep, height: sepH));
        totalH += sepH;
        continue;
      }
      final isFirst = line == headerLines.first;
      final isBold =
          isFirst ||
          line == 'QUOTATION' ||
          line.startsWith('Date:') ||
          line.startsWith('Customer:');
      final sz = isFirst ? 28.0 : (line.startsWith('Customer:') ? 24.0 : 22.0);
      final tp = _makeTp(line, sz, isBold);
      tp.layout(maxWidth: cw);
      lineInfos.add(
        _LineInfo(
          type: _LineType.centered,
          height: tp.height + lineGap,
          painter: tp,
        ),
      );
      totalH += tp.height + lineGap;
    }

    // Sep
    lineInfos.add(_LineInfo(type: _LineType.sep, height: sepH));
    totalH += sepH;

    // Table header
    final hdrSno = _makeTp('#', 20, true);
    final hdrPart = _makeTp('Item', 20, true);
    final hdrQty = _makeTp('Qty', 20, true);
    final hdrRate = _makeTp('Rate', 20, true);
    final hdrAmt = _makeTp('Amt', 20, true);
    hdrSno.layout(maxWidth: _snoW);
    hdrPart.layout(maxWidth: _partW);
    hdrQty.layout(maxWidth: _qtyW);
    hdrRate.layout(maxWidth: _rateW);
    hdrAmt.layout(maxWidth: _amtW);
    final hdrH = hdrSno.height + lineGap;
    lineInfos.add(
      _LineInfo(
        type: _LineType.tableRow,
        height: hdrH,
        painters: [hdrSno, hdrPart, hdrQty, hdrRate, hdrAmt],
      ),
    );
    totalH += hdrH;

    // Sep
    lineInfos.add(_LineInfo(type: _LineType.sep, height: sepH));
    totalH += sepH;

    // Data rows
    for (final row in rows) {
      final sno = _makeTp('${row.sNo}', 24, true);
      // Truncate product name smartly — avoid cutting mid-word or mid-Tamil glyph
      var productName = row.productName;
      if (productName.length > 22) {
        // Try to break at last space before 22 chars
        final cutPoint = productName.lastIndexOf(' ', 22);
        if (cutPoint > 14) {
          productName = '${productName.substring(0, cutPoint)}…';
        } else {
          productName = '${productName.substring(0, 20)}…';
        }
      }
      final part = _makeTp(
        productName,
        24,
        true,
      );
      final qty = _makeTp('${row.qty}', 24, true);
      final rate = _makeTp(row.rate.toStringAsFixed(2), 24, true);
      final amt = _makeTp(row.amount.toStringAsFixed(2), 24, true);
      sno.layout(maxWidth: _snoW);
      part.layout(maxWidth: _partW);
      qty.layout(maxWidth: _qtyW);
      rate.layout(maxWidth: _rateW);
      amt.layout(maxWidth: _amtW);
      final h = [
        sno,
        part,
        qty,
        rate,
        amt,
      ].fold<double>(0, (prev, tp) => tp.height > prev ? tp.height : prev);
      lineInfos.add(
        _LineInfo(
          type: _LineType.tableRow,
          height: h + lineGap,
          painters: [sno, part, qty, rate, amt],
        ),
      );
      totalH += h + lineGap;
    }

    // Sep
    lineInfos.add(_LineInfo(type: _LineType.sep, height: sepH));
    totalH += sepH;

    // Totals
    for (final line in totalLines) {
      if (line.startsWith('\u2500') || line.startsWith('-')) {
        lineInfos.add(_LineInfo(type: _LineType.sep, height: sepH));
        totalH += sepH;
        continue;
      }
      final isNetTotal = line.startsWith('NET TOTAL');
      final isTotalItems = line.startsWith('Total Items');
      final isBold = isNetTotal || line.startsWith('Total');
      final sz = isNetTotal ? 24.0 : 20.0;
      final tp = _makeTp(line, sz, isBold);
      tp.layout(maxWidth: cw);
      lineInfos.add(
        _LineInfo(
          type: isNetTotal
              ? _LineType.centered
              : (isTotalItems ? _LineType.leftAligned : _LineType.centered),
          height: tp.height + lineGap,
          painter: tp,
        ),
      );
      totalH += tp.height + lineGap;
    }

    // Footer
    for (final line in footerLines) {
      if (line.isEmpty) continue;
      final tp = _makeTp(line, 20, false);
      tp.layout(maxWidth: cw);
      lineInfos.add(
        _LineInfo(
          type: _LineType.centered,
          height: tp.height + lineGap,
          painter: tp,
        ),
      );
      totalH += tp.height + lineGap;
    }

    totalH += 10;

    // Phase 2: render to image
    final width = cw.toInt();
    final height = totalH.ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.drawColor(Colors.white, BlendMode.src);

    double y = 10;
    for (final li in lineInfos) {
      switch (li.type) {
        case _LineType.empty:
          y += li.height;
        case _LineType.sep:
          final paint = Paint()
            ..color = Colors.black
            ..strokeWidth = 1;
          canvas.drawLine(
            Offset(0, y + 1),
            Offset(width.toDouble(), y + 1),
            paint,
          );
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
        case _LineType.tableRow:
          // Render at fixed pixel positions
          if (li.painters != null && li.painters!.length >= 5) {
            // S.No - center in column
            final snoCx = _snoX + (_snoW - li.painters![0].width) / 2;
            li.painters![0].paint(canvas, Offset(snoCx, y));
            // Particulars - left aligned
            li.painters![1].paint(canvas, Offset(_partX, y));
            // Qty - right aligned
            final qtyRx = _qtyX + _qtyW - li.painters![2].width;
            li.painters![2].paint(canvas, Offset(qtyRx, y));
            // Rate - right aligned
            final rateRx = _rateX + _rateW - li.painters![3].width;
            li.painters![3].paint(canvas, Offset(rateRx, y));
            // Amount - right aligned
            final amtRx = _amtX + _amtW - li.painters![4].width;
            li.painters![4].paint(canvas, Offset(amtRx, y));
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

enum _LineType { empty, sep, centered, leftAligned, rightAligned, tableRow }

class _LineInfo {
  final _LineType type;
  final double height;
  final TextPainter? painter;
  final List<TextPainter>? painters;

  _LineInfo({
    required this.type,
    required this.height,
    this.painter,
    this.painters,
  });
}
