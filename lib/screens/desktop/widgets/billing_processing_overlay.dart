import 'package:flutter/material.dart';

class BillingProcessingOverlay extends StatelessWidget {
  final bool isProcessing;

  const BillingProcessingOverlay({super.key, required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    if (!isProcessing) return const SizedBox.shrink();
    return Container(
      color: Colors.black.withValues(alpha: 0.3),
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Processing...', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
