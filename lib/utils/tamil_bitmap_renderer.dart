import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'qty_format.dart';

class ThermalColumnLayout {
  ThermalColumnLayout._();
  static const double printableWidthPx = 624;
  static const double dpi = 203;
}

class ThermalRow {
  final int sNo;
  final String productName;
  final double qty;
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
  static const double _canvasW = 610;

  static const double _snoX = 2;
  static const double _snoW = 35;

  static const double _partX = 37;
  static const double _partW = 270;

  static const double _qtyX = 307;
  static const double _qtyW = 45;

  static const double _rateX = 352;
  static const double _rateW = 90;

  static const double _amtX = 442;
  static const double _amtW = 100;

  static const double _tableRight = 542;
  static const double _lineGap = 1.5;
  static const double _topPad = 2.0;

  static Future<Uint8List> renderToBitmap(
    String text, {
    double fontSize = 32,
    double maxWidth = 624,
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

  /// The Windows thermal bill as one picture (redesigned 18 Oct 2026, owner:
  /// "more professional"):
  ///   shop name · QUOTATION on a black band · bill no | date and time ·
  ///   customer · item table with rules only (no box round every cell) ·
  ///   totals in a money column · NET TOTAL on a black band · amount in
  ///   words · how it was paid · thank you.
  static Future<Uint8List> renderReceiptAsImage({
    required List<String> headerLines,
    required List<ThermalRow> rows,
    required List<String> totalLines,
    required List<String> footerLines,
    double fontSize = 24,
  }) async {
    const left = _snoX;
    const right = _tableRight;
    const width = right - left;
    final blocks = <_Block>[];

    void gap(double h) => blocks.add(_Block(h, (_, __) {}));

    void rule({double thick = 1, bool dashed = false}) => blocks.add(
          _Block(thick + 4, (c, y) {
            final paint = Paint()
              ..color = Colors.black
              ..strokeWidth = thick;
            final ly = y + 2 + thick / 2;
            if (!dashed) {
              c.drawLine(const Offset(left, 0) + Offset(0, ly), Offset(right, ly), paint);
            } else {
              for (var x = left; x < right; x += 10) {
                c.drawLine(Offset(x, ly), Offset(x + 5 > right ? right : x + 5, ly), paint);
              }
            }
          }),
        );

    void centered(String text, double size, {bool bold = false}) {
      final tp = _makeTp(text, size, bold)..layout(maxWidth: width);
      blocks.add(_Block(tp.height + _lineGap, (c, y) => tp.paint(c, Offset(left + (width - tp.width) / 2, y))));
    }

    void leftText(String text, double size, {bool bold = false}) {
      final tp = _makeTp(text, size, bold)..layout(maxWidth: width);
      blocks.add(_Block(tp.height + _lineGap, (c, y) => tp.paint(c, Offset(left + 2, y))));
    }

    void twoSides(String l, String r, double size, {bool bold = false}) {
      final a = _makeTp(l, size, bold)..layout(maxWidth: width / 2);
      final b = _makeTp(r, size, bold)..layout(maxWidth: width);
      final h = (a.height > b.height ? a.height : b.height) + _lineGap;
      blocks.add(_Block(h, (c, y) {
        a.paint(c, Offset(left + 2, y));
        b.paint(c, Offset(right - b.width - 2, y));
      }));
    }

    /// Bold text in a thin box across the bill (owner, 18 Oct 2026: no
    /// solid black band; an outline prints faster and uses less paper).
    void band(String l, String? r, double size) {
      final a = _makeTp(l, size, true)..layout(maxWidth: width);
      final b = r == null ? null : (_makeTp(r, size, true)..layout(maxWidth: width));
      final h = a.height + 10;
      blocks.add(_Block(h, (c, y) {
        c.drawRect(
          Rect.fromLTWH(left + 1, y + 1, width - 2, h - 2),
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        if (b == null) {
          a.paint(c, Offset(left + (width - a.width) / 2, y + 5));
        } else {
          a.paint(c, Offset(left + 10, y + 5));
          b.paint(c, Offset(right - b.width - 10, y + 5));
        }
      }));
    }

    /// "Label:  amount", the amount right-aligned in the money column.
    void money(String label, String value, double size, {bool bold = false}) {
      final a = _makeTp(label, size, bold)..layout(maxWidth: width);
      final b = _makeTp(value, size, bold)..layout(maxWidth: width);
      final h = (a.height > b.height ? a.height : b.height) + _lineGap;
      blocks.add(_Block(h, (c, y) {
        final vx = right - b.width - 4;
        var lx = _amtX - a.width - 10;
        if (lx + a.width + 10 > vx) lx = vx - a.width - 10;
        a.paint(c, Offset(lx < left ? left : lx, y));
        b.paint(c, Offset(vx, y));
      }));
    }

    // ── header ──
    String? billNo, dateTime;
    for (final line in headerLines) {
      if (line.isEmpty) continue;
      if (line == headerLines.first) {
        centered(line, 36, bold: true);
      } else if (line == 'QUOTATION') {
        rule();
        final tp = _makeTp('QUOTATION', 26, true, letterSpacing: 6)..layout(maxWidth: width);
        blocks.add(_Block(tp.height + 2, (c, y) => tp.paint(c, Offset(left + (width - tp.width) / 2, y + 1))));
        rule();
        gap(4);
      } else if (line.startsWith('Bill No:')) {
        billNo = line;
      } else if (line.startsWith('Date:')) {
        dateTime = line.replaceFirst('Date: ', '').replaceFirst('  Time: ', '  ');
      } else if (line.startsWith('Customer:')) {
        if (billNo != null || dateTime != null) {
          twoSides(billNo ?? '', dateTime ?? '', 20);
          billNo = dateTime = null;
        }
        leftText(line, 24, bold: true);
      } else {
        centered(line, 20);
      }
    }
    if (billNo != null || dateTime != null) twoSides(billNo ?? '', dateTime ?? '', 20);
    gap(4);

    // ── table: rules only ──
    rule(thick: 2);
    final heads = [
      _makeTp('#', 20, true)..layout(maxWidth: _snoW),
      _makeTp('Item', 20, true)..layout(maxWidth: _partW),
      _makeTp('Qty', 20, true)..layout(maxWidth: _qtyW + 10),
      _makeTp('Rate', 20, true)..layout(maxWidth: _rateW),
      _makeTp('Amount', 20, true)..layout(maxWidth: _amtW),
    ];
    blocks.add(_Block(heads[0].height + 4, (c, y) => _paintRow(c, y + 2, heads)));
    rule();
    for (final row in rows) {
      final cells = [
        _makeTp('${row.sNo}', 24, false)..layout(maxWidth: _snoW),
        _makeTp(row.productName, 24, true)..layout(maxWidth: _partW - 6),
        _makeTp(formatQty(row.qty), 24, true)..layout(maxWidth: _qtyW + 10),
        _makeTp(row.rate.toStringAsFixed(2), 24, false)..layout(maxWidth: _rateW),
        _makeTp(row.amount.toStringAsFixed(2), 24, true)..layout(maxWidth: _amtW),
      ];
      final h = cells.fold<double>(0, (m, t) => t.height > m ? t.height : m) + 6;
      blocks.add(_Block(h, (c, y) => _paintRow(c, y + 3, cells)));
    }
    rule();

    // ── totals ──
    for (final line in totalLines) {
      final colon = line.indexOf(':');
      if (line.startsWith('Total Items')) {
        leftText(line, 20, bold: true);
      } else if (line.startsWith('NET TOTAL')) {
        gap(4);
        band('NET TOTAL', '₹${line.substring(colon + 1).trim()}', 30);
        gap(4);
      } else if (line.startsWith('Rupees') || line.endsWith('Only')) {
        centered(line, 19);
        gap(4);
      } else if (colon > 0) {
        final due = line.startsWith('Balance Due');
        money(line.substring(0, colon + 1), line.substring(colon + 1).trim(), due ? 26 : 22, bold: due);
      } else {
        leftText(line, 20);
      }
    }

    // ── footer ──
    gap(6);
    rule(dashed: true);
    for (final line in footerLines) {
      centered(line, 24, bold: true);
    }
    gap(10);

    final totalH = blocks.fold<double>(_topPad, (t, b) => t + b.height);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, _canvasW, totalH));
    canvas.drawColor(Colors.white, BlendMode.src);
    var y = _topPad;
    for (final b in blocks) {
      b.paint(canvas, y);
      y += b.height;
    }
    final image = await recorder.endRecording().toImage(_canvasW.toInt(), totalH.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  }

  /// One table row: # centred, item from the left, numbers right-aligned.
  static void _paintRow(Canvas c, double y, List<TextPainter> cells) {
    cells[0].paint(c, Offset(_snoX + (_snoW - cells[0].width) / 2, y));
    cells[1].paint(c, Offset(_partX + 4, y));
    cells[2].paint(c, Offset(_qtyX + _qtyW - cells[2].width - 2, y));
    cells[3].paint(c, Offset(_rateX + _rateW - cells[3].width - 4, y));
    cells[4].paint(c, Offset(_amtX + _amtW - cells[4].width - 4, y));
  }

  static TextPainter _makeTp(
    String text,
    double fontSize,
    bool bold, {
    Color color = Colors.black,
    double? letterSpacing,
  }) {
    final hasTamil = RegExp(r'[\u0B80-\u0BFF]').hasMatch(text);
    final fontFamily = hasTamil ? 'Nirmala UI' : 'NotoSans';

    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontFamily: fontFamily,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          height: hasTamil ? 1.2 : null,
          letterSpacing: letterSpacing,
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

/// One horizontal slice of the bill: its height and how to draw it.
class _Block {
  _Block(this.height, this.paint);
  final double height;
  final void Function(Canvas canvas, double y) paint;
}
