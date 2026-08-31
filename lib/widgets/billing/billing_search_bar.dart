import 'package:flutter/material.dart';

import '../../models/product.dart';

class BillingSearchBar extends StatelessWidget {
  const BillingSearchBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.qtyController,
    required this.qtyFocusNode,
    required this.priceController,
    required this.priceFocusNode,
    required this.totalController,
    required this.totalFocusNode,
    required this.costController,
    required this.costFocusNode,
    required this.searchMode,
    required this.selectedProduct,
    required this.editingCartIndex,
    required this.selectedUnitType,
    required this.onSearchModeToggle,
    required this.onSearchChanged,
    required this.onNewProduct,
    required this.onQtySubmitted,
    required this.onQtyChanged,
    required this.onPriceSubmitted,
    required this.onPriceChanged,
    required this.onTotalSubmitted,
    required this.onTotalChanged,
    required this.onCostSubmitted,
    required this.onUnitTypeChanged,
    required this.onCancelEdit,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final TextEditingController qtyController;
  final FocusNode qtyFocusNode;
  final TextEditingController priceController;
  final FocusNode priceFocusNode;
  final TextEditingController totalController;
  final FocusNode totalFocusNode;
  final TextEditingController costController;
  final FocusNode costFocusNode;
  final String searchMode;
  final Product? selectedProduct;
  final int editingCartIndex;
  final String selectedUnitType;
  final VoidCallback onSearchModeToggle;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onNewProduct;
  final ValueChanged<String> onQtySubmitted;
  final ValueChanged<String> onQtyChanged;
  final ValueChanged<String> onPriceSubmitted;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<String> onTotalSubmitted;
  final ValueChanged<String> onTotalChanged;
  final ValueChanged<String> onCostSubmitted;
  final ValueChanged<String?> onUnitTypeChanged;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedProduct == null && editingCartIndex < 0)
            _buildSearchMode()
          else
            _buildEntryMode(),
        ],
      ),
    );
  }

  Widget _buildSearchMode() {
    return Row(
      children: [
        GestureDetector(
          onTap: onSearchModeToggle,
          child: Semantics(
            label: 'Toggle search mode',
            button: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                color: searchMode == 'sfw'
                    ? const Color(0xFF667eea)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                searchMode == 'sfw' ? 'SFW' : 'Name',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: searchMode == 'sfw'
                      ? Colors.white
                      : Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            label: 'Product search',
            child: TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              decoration: InputDecoration(
                hintText: searchMode == 'sfw'
                    ? 'Type SFW code... (e.g., ml5)'
                    : 'Type product name or code...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              style: const TextStyle(fontSize: 16),
              onChanged: onSearchChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: 'Add new product',
          button: true,
          child: OutlinedButton.icon(
            onPressed: onNewProduct,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Product'),
          ),
        ),
      ],
    );
  }

  Widget _buildEntryMode() {
    return Row(
      children: [
        if (editingCartIndex >= 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'EDIT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (editingCartIndex >= 0
                      ? Colors.orange
                      : const Color(0xFF667eea))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              selectedProduct?.name ?? '',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: editingCartIndex >= 0
                    ? Colors.orange
                    : const Color(0xFF667eea),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Semantics(
            label: 'Unit type',
            child: DropdownButton<String>(
              value: selectedUnitType,
              isDense: true,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 11, color: Colors.black),
              items: const [
                DropdownMenuItem(value: 'pieces', child: Text('Pcs')),
                DropdownMenuItem(value: 'pack', child: Text('Pack')),
                DropdownMenuItem(value: 'saram', child: Text('Saram')),
                DropdownMenuItem(value: 'box', child: Text('Box')),
              ],
              onChanged: onUnitTypeChanged,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 70,
          child: Semantics(
            label: 'Quantity',
            child: TextField(
              controller: qtyController,
              focusNode: qtyFocusNode,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'Qty',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                isDense: true,
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              onSubmitted: onQtySubmitted,
              onChanged: onQtyChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Semantics(
            label: 'Price',
            child: TextField(
              controller: priceController,
              focusNode: priceFocusNode,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'Price',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
              onSubmitted: onPriceSubmitted,
              onChanged: onPriceChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Semantics(
            label: 'Total',
            child: TextField(
              controller: totalController,
              focusNode: totalFocusNode,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'Total',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                isDense: true,
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              onSubmitted: onTotalSubmitted,
              onChanged: onTotalChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: Semantics(
            label: 'Cost price',
            child: TextField(
              controller: costController,
              focusNode: costFocusNode,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'Cost',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
              onSubmitted: onCostSubmitted,
            ),
          ),
        ),
        if (editingCartIndex >= 0) ...[
          const SizedBox(width: 6),
          Semantics(
            label: 'Cancel edit',
            button: true,
            child: IconButton(
              onPressed: onCancelEdit,
              icon: const Icon(Icons.close, size: 18, color: Colors.red),
              tooltip: 'Cancel edit (ESC)',
            ),
          ),
        ],
      ],
    );
  }
}
