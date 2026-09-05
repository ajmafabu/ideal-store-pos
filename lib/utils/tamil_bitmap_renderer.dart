import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ThermalColumnLayout {
  ThermalColumnLayout._();
  static const double printableWidthPx = 500;
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
  static const double _canvasW = 500;

  static const double _startX = 5.0;

  static const double _snoX = 5;
  static const double _snoW = 25;

  static const double _partX = 30;
  static const double _partW = 240;

  static const double _qtyX = 270;
  static const double _qtyW = 45;

  static const double _rateX = 315;
  static const double _rateW = 85;

  static const double _amtX = 400;
  static const double _amtW = 90;

  static const double _borderH = 1.0;
  static const double _cellPadY = 3.0;
  static const double _tamilRowPad = 6.0;
  static const double _lineGap = 2.0;
  static const double _topPad = 5.0;

  static Future<Uint8List> renderToBitmap(
    String text, {
    double fontSize = 32,
    double maxWidth = 500,
    bool bold = false,
  }) async {
    if (text.isEmpty) return Uint8List(0);

    final hasTamil = RegExp(r'[\u0B80-\u0BFF]').hasMatch(text);
    final fontFamily = hasTamil ? 'Nirmala UI' : 'NotoSans';

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
    final List<_LineInfo> lineInfos = [];
    double totalH = _topPad;

    for (final line in headerLines) {
      if (line.isEmpty) {
        lineInfos.add(_LineInfo(type: _LineType.empty, height: 4));
        totalH += 4;
        continue;
      }
      final isFirst = line == headerLines.first;
      final isBold =
          isFirst ||
          line == 'QUOTATION' ||
          line.startsWith('Date:') ||
          line.startsWith('Customer:');
      final sz = isFirst
          ? 28.0
          : (line == 'QUOTATION'
              ? 24.0
              : (line.startsWith('Customer:') ? 20.0 : 18.0));
      final tp = _makeTp(line, sz, isBold);
      tp.layout(maxWidth: _canvasW - 20);
      lineInfos.add(
        _LineInfo(
          type: _LineType.centered,
          height: tp.height + _lineGap,
          painter: tp,
        ),
      );
      totalH += tp.height + _lineGap;
    }

    lineInfos.add(_LineInfo(type: _LineType.borderTop, height: _borderH));
    totalH += _borderH;

    final hdrSno = _makeTp('#', 18, true);
    final hdrPart = _makeTp('Item', 18, true);
    final hdrQty = _makeTp('Qty', 18, true);
    final hdrRate = _makeTp('Rate', 18, true);
    final hdrAmt = _makeTp('Amt', 18, true);
    hdrSno.layout(maxWidth: _snoW);
    hdrPart.layout(maxWidth: _partW - 4);
    hdrQty.layout(maxWidth: _qtyW);
    hdrRate.layout(maxWidth: _rateW);
    hdrAmt.layout(maxWidth: _amtW - 4);
    final hdrH = hdrSno.height + _cellPadY * 2;
    lineInfos.add(
      _LineInfo(
        type: _LineType.tableRow,
        height: hdrH,
        painters: [hdrSno, hdrPart, hdrQty, hdrRate, hdrAmt],
      ),
    );
    totalH += hdrH;

    lineInfos.add(_LineInfo(type: _LineType.borderRow, height: _borderH));
    totalH += _borderH;

    for (final row in rows) {
      final sno = _makeTp('${row.sNo}', 20, true);
      final part = _makeTp(row.productName, 20, true);
      final qty = _makeTp('${row.qty}', 20, true);
      final rate = _makeTp(row.rate.toStringAsFixed(2), 20, true);
      final amt = _makeTp(row.amount.toStringAsFixed(2), 20, true);

      sno.layout(maxWidth: _snoW);
      part.layout(maxWidth: _partW);
      qty.layout(maxWidth: _qtyW);
      rate.layout(maxWidth: _rateW);
      amt.layout(maxWidth: _amtW);

      final maxH = [sno, part, qty, rate, amt]
          .fold<double>(0, (prev, tp) => tp.height > prev ? tp.height : prev);

      final hasTamil = RegExp(r'[\u0B80-\u0BFF]').hasMatch(row.productName);
      final rowPadExtra = hasTamil ? _tamilRowPad : 0.0;

      lineInfos.add(
        _LineInfo(
          type: _LineType.tableRow,
          height: maxH + _cellPadY * 2 + rowPadExtra,
          painters: [sno, part, qty, rate, amt],
        ),
      );
      totalH += maxH + _cellPadY * 2 + rowPadExtra;

      lineInfos.add(_LineInfo(type: _LineType.borderRow, height: _borderH));
      totalH += _borderH;
    }

    for (final line in totalLines) {
      final isNetTotal = line.startsWith('NET TOTAL');
      final isTotalItems = line.startsWith('Total Items');
      final isBold = isNetTotal || line.startsWith('Total');
      final sz = isNetTotal ? 24.0 : 18.0;
      final tp = _makeTp(line, sz, isBold);
      tp.layout(maxWidth: _canvasW - 20);
      lineInfos.add(
        _LineInfo(
          type: isNetTotal
              ? _LineType.centered
              : (isTotalItems ? _LineType.leftAligned : _LineType.centered),
          height: tp.height + _lineGap,
          painter: tp,
        ),
      );
      totalH += tp.height + _lineGap;
    }

    for (final line in footerLines) {
      if (line.isEmpty) continue;
      final tp = _makeTp(line, 18, false);
      tp.layout(maxWidth: _canvasW - 20);
      lineInfos.add(
        _LineInfo(
          type: _LineType.centered,
          height: tp.height + _lineGap,
          painter: tp,
        ),
      );
      totalH += tp.height + _lineGap;
    }

    totalH += _topPad;

    final width = _canvasW.toInt();
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

    double y = _topPad;
    for (final li in lineInfos) {
      switch (li.type) {
        case _LineType.empty:
          y += li.height;
        case _LineType.borderTop:
          canvas.drawLine(
            Offset(_snoX, y),
            Offset(_amtX + _amtW, y),
            borderPaint,
          );
          y += li.height;
        case _LineType.borderRow:
          canvas.drawLine(
            Offset(_snoX, y),
            Offset(_amtX + _amtW, y),
            borderPaint,
          );
          y += li.height;
        case _LineType.sep:
          y += li.height;
        case _LineType.centered:
          if (li.painter != null) {
            final cx = (_canvasW - li.painter!.width) / 2;
            li.painter!.paint(canvas, Offset(cx > _startX ? cx : _startX, y));
          }
          y += li.height;
        case _LineType.leftAligned:
          if (li.painter != null) {
            li.painter!.paint(canvas, Offset(_startX, y));
          }
          y += li.height;
        case _LineType.rightAligned:
          if (li.painter != null) {
            final rx = _amtX + _amtW - li.painter!.width;
            li.painter!.paint(canvas, Offset(rx > 0 ? rx : 0, y));
          }
          y += li.height;
        case _LineType.tableRow:
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

          if (li.painters != null && li.painters!.length >= 5) {
            for (int i = 0; i < 5; i++) {
              final tp = li.painters![i];
              final cellY = y + (li.height - tp.height) / 2;
              double cellX;
              if (i == 0) {
                cellX = _snoX + 2;
              } else if (i == 1) {
                cellX = _partX + 4;
              } else {
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
    final fontFamily = hasTamil ? 'Nirmala UI' : 'NotoSans';

    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.black,
          fontFamily: fontFamily,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          height: hasTamil ? 1.3 : null,
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
