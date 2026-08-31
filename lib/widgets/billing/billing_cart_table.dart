import 'package:flutter/material.dart';

import '../../config/desktop_billing_provider.dart';

class BillingCartTable extends StatelessWidget {
  const BillingCartTable({
    super.key,
    required this.session,
    required this.scrollController,
    required this.selectedIndex,
    required this.onItemTap,
    required this.onItemEdit,
    required this.onItemDelete,
  });

  final SaleSession session;
  final ScrollController scrollController;
  final int selectedIndex;
  final ValueChanged<int> onItemTap;
  final ValueChanged<int> onItemEdit;
  final ValueChanged<int> onItemDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: session.items.isEmpty ? _buildEmptyState() : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF667eea),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '#',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              'Product',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'Qty',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Price',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Total',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No items in cart',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Type product name to add',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      controller: scrollController,
      itemCount: session.items.length,
      itemBuilder: (context, index) {
        final item = session.items[index];
        final isSelected = index == selectedIndex;
        return Container(
          key: ValueKey('cart_${item.productId}_$index'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: isSelected
              ? const Color(0xFF667eea).withValues(alpha: 0.1)
              : null,
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Expanded(
                flex: 4,
                child: Semantics(
                  label: '${item.name}, qty ${item.qty}',
                  button: true,
                  child: GestureDetector(
                    onTap: () => onItemTap(index),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (item.tamilName != null &&
                            item.tamilName!.isNotEmpty)
                          Text(
                            item.tamilName!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${item.qty}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  'Rs${item.price.toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  'Rs${item.total.toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Semantics(
                label: 'Edit ${item.name}',
                button: true,
                child: SizedBox(
                  width: 24,
                  child: GestureDetector(
                    onTap: () => onItemEdit(index),
                    child: const Icon(
                      Icons.edit,
                      size: 16,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),
              Semantics(
                label: 'Delete ${item.name}',
                button: true,
                child: SizedBox(
                  width: 24,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.red,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => onItemDelete(index),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
