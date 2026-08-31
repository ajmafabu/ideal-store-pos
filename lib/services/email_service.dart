import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_mailer/flutter_mailer.dart';
import 'package:path_provider/path_provider.dart';
import '../models/sale.dart';
import '../utils/logger.dart';

class EmailService {
  Future<bool> sendInvoiceEmail({
    required BuildContext context,
    required String toEmail,
    required Sale sale,
    required List<int> pdfBytes,
    required String shopName,
  }) async {
    final invoiceId = sale.id.isNotEmpty
        ? (sale.id.length >= 8 ? sale.id.substring(0, 8).toUpperCase() : sale.id.toUpperCase())
        : sale.createdAt.millisecondsSinceEpoch.toRadixString(16).substring(0, 8).toUpperCase();

    final itemSummary = sale.items
        .take(5)
        .map((item) => '  ${item.name} x${item.qty} = Rs${item.total.toStringAsFixed(2)}')
        .join('\n');
    final remainingItems = sale.items.length > 5 ? '\n  ...and ${sale.items.length - 5} more items' : '';

    final body = '''
Thank you for your purchase at $shopName!

Invoice: #$invoiceId
Date: ${sale.createdAt.day}/${sale.createdAt.month}/${sale.createdAt.year}
Items: ${sale.items.length}
Total: Rs${sale.finalAmount.toStringAsFixed(2)}
Payment: ${sale.paymentMethod.toUpperCase()}
${sale.isCredit ? 'Due: Rs${sale.dueAmount.toStringAsFixed(2)}' : ''}

Items:
$itemSummary$remainingItems

Please find the detailed invoice attached as PDF.

 Regards,
$shopName
''';

    try {
      final tempDir = await getTemporaryDirectory();
      final invoiceFile = File('${tempDir.path}/invoice_$invoiceId.pdf');
      await invoiceFile.writeAsBytes(pdfBytes);

      final mailOptions = MailOptions(
        subject: 'Invoice from $shopName - #$invoiceId',
        recipients: [toEmail],
        body: body,
        attachments: [invoiceFile.path],
      );

      final response = await FlutterMailer.send(mailOptions);
      final success = response == MailerResponse.sent || response == MailerResponse.saved;

      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email app opened successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (response == MailerResponse.cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email cancelled by user'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Email failed: $response'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      try {
        await invoiceFile.delete();
      } catch (e) {
        Logger.warning('Failed to delete temporary invoice file: $e');
      }

      return success;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
}
