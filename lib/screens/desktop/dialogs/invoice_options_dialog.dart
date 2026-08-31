import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/sale.dart';
import '../../admin/barcode_label_screen.dart';

class InvoiceOptionsDialog extends StatefulWidget {
  final Sale sale;

  const InvoiceOptionsDialog({super.key, required this.sale});

  @override
  State<InvoiceOptionsDialog> createState() => _InvoiceOptionsDialogState();
}

class _InvoiceOptionsDialogState extends State<InvoiceOptionsDialog> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
          Navigator.pop(context, 'skip');
        } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
          Navigator.pop(context, 'print_usb');
        } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
          Navigator.pop(context, 'print');
        } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
          Navigator.pop(context, 'pdf');
        } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
          Navigator.pop(context, 'whatsapp');
        } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
          Navigator.pop(context, 'email');
        } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
          Navigator.pop(context, 'barcode');
        } else if (key == LogicalKeyboardKey.escape) {
          Navigator.pop(context, 'skip');
        }
      },
      child: AlertDialog(
        title: Text('Sale Completed! Rs ${widget.sale.finalAmount.toStringAsFixed(2)}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
                children: [
                  _InvoiceOptionButton(
                    icon: Icons.close,
                    label: 'Skip',
                    shortcut: '1',
                    color: Colors.grey,
                    onTap: () => Navigator.pop(context, 'skip'),
                  ),
                  _InvoiceOptionButton(
                    icon: Icons.usb,
                    label: 'Print USB',
                    shortcut: '2',
                    color: Colors.blue,
                    onTap: () => Navigator.pop(context, 'print_usb'),
                  ),
                  _InvoiceOptionButton(
                    icon: Icons.bluetooth,
                    label: 'Print BT',
                    shortcut: '3',
                    color: Colors.blue,
                    onTap: () => Navigator.pop(context, 'print'),
                  ),
                  _InvoiceOptionButton(
                    icon: Icons.picture_as_pdf,
                    label: 'PDF',
                    shortcut: '4',
                    color: Colors.green,
                    onTap: () => Navigator.pop(context, 'pdf'),
                  ),
                  _InvoiceOptionButton(
                    icon: Icons.share,
                    label: 'WhatsApp',
                    shortcut: '5',
                    color: Colors.green,
                    onTap: () => Navigator.pop(context, 'whatsapp'),
                  ),
                  _InvoiceOptionButton(
                    icon: Icons.email,
                    label: 'Email',
                    shortcut: '6',
                    color: Colors.green,
                    onTap: () => Navigator.pop(context, 'email'),
                  ),
                  _InvoiceOptionButton(
                    icon: Icons.qr_code,
                    label: 'Barcode',
                    shortcut: '7',
                    color: Colors.purple,
                    onTap: () => Navigator.pop(context, 'barcode'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _InvoiceOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String shortcut;
  final Color color;
  final VoidCallback onTap;

  const _InvoiceOptionButton({
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              '[$shortcut]',
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
