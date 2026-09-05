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
  static const double _snoW = 20;
  static const double _partX = 22;
  static const double _partW = 242;
  static const double _qtyX = 264;
  static const double _qtyW = 36;
  static const double _rateX = 302;
  static const double _rateW = 100;
  static const double _amtX = 404;
  static const double _amtW = 172;
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
    const lineGap = 6.0;
    const cellPadY = 4.0;

    final List<_LineInfo> lineInfos = [];
    double totalH = 5;

    for (final line in headerLines) {
      if (line.isEmpty) {
        lineInfos.add(_LineInfo(type: _LineType.empty, height: 8));
        totalH += 8;
        continue;
      }
      final isFirst = line == headerLines.first;
      final isBold =
          isFirst ||
          line == 'QUOTATION' ||
          line.startsWith('Date:') ||
          line.startsWith('Customer:');
      final sz = isFirst
          ? 32.0
          : (line == 'QUOTATION'
              ? 28.0
              : (line.startsWith('Customer:') ? 24.0 : 22.0));
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

    // Top border of table
    lineInfos.add(_LineInfo(type: _LineType.borderTop, height: _borderH));
    totalH += _borderH;

    // Table header
    final hdrSno = _makeTp('#', 22, true);
    final hdrPart = _makeTp('Item', 22, true);
    final hdrQty = _makeTp('Qty', 22, true);
    final hdrRate = _makeTp('Rate', 22, true);
    final hdrAmt = _makeTp('Amt', 22, true);
    hdrSno.layout(maxWidth: _snoW);
    hdrPart.layout(maxWidth: _partW);
    hdrQty.layout(maxWidth: _qtyW);
    hdrRate.layout(maxWidth: _rateW);
    hdrAmt.layout(maxWidth: _amtW);
    final hdrH = hdrSno.height + cellPadY * 2;
    lineInfos.add(
      _LineInfo(
        type: _LineType.tableRow,
        height: hdrH,
        painters: [hdrSno, hdrPart, hdrQty, hdrRate, hdrAmt],
      ),
    );
    totalH += hdrH;

    // Border after header
    lineInfos.add(_LineInfo(type: _LineType.borderRow, height: _borderH));
    totalH += _borderH;

    // Data rows
    for (final row in rows) {
      final sno = _makeTp('${row.sNo}', 26, true);
      var productName = row.productName;
      if (productName.length > 20) {
        final cutPoint = productName.lastIndexOf(' ', 20);
        if (cutPoint > 10) {
          productName = '${productName.substring(0, cutPoint)}…';
        } else {
          productName = '${productName.substring(0, 18)}…';
        }
      }
      final part = _makeTp(productName, 26, true);
      final qty = _makeTp('${row.qty}', 26, true);
      final rate = _makeTp(row.rate.toStringAsFixed(2), 26, true);
      final amt = _makeTp(row.amount.toStringAsFixed(2), 26, true);
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
          height: h + cellPadY * 2,
          painters: [sno, part, qty, rate, amt],
        ),
      );
      totalH += h + cellPadY * 2;

      // Border after each data row
      lineInfos.add(_LineInfo(type: _LineType.borderRow, height: _borderH));
      totalH += _borderH;
    }

    // Totals
    for (final line in totalLines) {
      final isNetTotal = line.startsWith('NET TOTAL');
      final isTotalItems = line.startsWith('Total Items');
      final isBold = isNetTotal || line.startsWith('Total');
      final sz = isNetTotal ? 30.0 : 22.0;
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
      final tp = _makeTp(line, 22, false);
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

    final width = cw.toInt();
    final height = totalH.ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.drawColor(Colors.white, BlendMode.src);

    final borderPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = _borderH;

    double y = 10;
    for (final li in lineInfos) {
      switch (li.type) {
        case _LineType.empty:
          y += li.height;
        case _LineType.borderTop:
          canvas.drawLine(
            Offset(0, y),
            Offset(_lineEnd, y),
            borderPaint,
          );
          y += li.height;
        case _LineType.borderRow:
          canvas.drawLine(
            Offset(0, y),
            Offset(_lineEnd, y),
            borderPaint,
          );
          y += li.height;
        case _LineType.sep:
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
          // Draw vertical borders
          final vLineTop = y;
          final vLineBot = y + li.height;
          canvas.drawLine(Offset(_snoX, vLineTop), Offset(_snoX, vLineBot), borderPaint);
          canvas.drawLine(Offset(_snoX + _snoW, vLineTop), Offset(_snoX + _snoW, vLineBot), borderPaint);
          canvas.drawLine(Offset(_partX, vLineTop), Offset(_partX, vLineBot), borderPaint);
          canvas.drawLine(Offset(_partX + _partW, vLineTop), Offset(_partX + _partW, vLineBot), borderPaint);
          canvas.drawLine(Offset(_qtyX, vLineTop), Offset(_qtyX, vLineBot), borderPaint);
          canvas.drawLine(Offset(_qtyX + _qtyW, vLineTop), Offset(_qtyX + _qtyW, vLineBot), borderPaint);
          canvas.drawLine(Offset(_rateX, vLineTop), Offset(_rateX, vLineBot), borderPaint);
          canvas.drawLine(Offset(_rateX + _rateW, vLineTop), Offset(_rateX + _rateW, vLineBot), borderPaint);
          canvas.drawLine(Offset(_amtX, vLineTop), Offset(_amtX, vLineBot), borderPaint);
          canvas.drawLine(Offset(_amtX + _amtW, vLineTop), Offset(_amtX + _amtW, vLineBot), borderPaint);

          // Render cell content
          if (li.painters != null && li.painters!.length >= 5) {
            final cellY = y + cellPadY;
            // S.No - left
            li.painters![0].paint(canvas, Offset(_snoX + 4, cellY));
            // Particulars - left
            li.painters![1].paint(canvas, Offset(_partX + 4, cellY));
            // Qty - right
            final qtyRx = _qtyX + _qtyW - li.painters![2].width - 4;
            li.painters![2].paint(canvas, Offset(qtyRx, cellY));
            // Rate - right
            final rateRx = _rateX + _rateW - li.painters![3].width - 4;
            li.painters![3].paint(canvas, Offset(rateRx, cellY));
            // Amount - right
            final amtRx = _amtX + _amtW - li.painters![4].width - 4;
            li.painters![4].paint(canvas, Offset(amtRx, cellY));
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
  sep,
  centered,
  leftAligned,
  rightAligned,
  tableRow,
  borderTop,
  borderRow,
}

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
