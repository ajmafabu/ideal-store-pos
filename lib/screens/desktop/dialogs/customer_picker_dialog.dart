import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/offline_service.dart';
import '../../../utils/logger.dart';

class CustomerPickerDialog extends StatefulWidget {
  final Function(String id, String name) onSelect;

  const CustomerPickerDialog({super.key, required this.onSelect});

  @override
  State<CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<CustomerPickerDialog> {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();
  int _selectedIndex = 0;
  final _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _selectCurrent() {
    if (_filtered.isEmpty || _selectedIndex >= _filtered.length) return;
    final customer = _filtered[_selectedIndex];
    widget.onSelect(customer['id'], customer['name']);
    Navigator.pop(context);
  }

  void _scrollSelectedIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listScrollController.hasClients) return;
      final targetOffset = _selectedIndex * 56.0;
      final viewport = _listScrollController.position.viewportDimension;
      final currentOffset = _listScrollController.offset;
      if (targetOffset < currentOffset) {
        _listScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else if (targetOffset > currentOffset + viewport - 60) {
        _listScrollController.animateTo(
          targetOffset - viewport + 100,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadCustomers() async {
    try {
      // Try online first
      final response = await Supabase.instance.client
          .from('customers')
          .select('id, name, phone')
          .order('name');
      setState(() {
        _customers = (response as List).cast<Map<String, dynamic>>();
        _filtered = _customers;
      });
    } catch (e) {
      Logger.warning('Failed to fetch customers online, using offline cache: $e');
      // Offline fallback: use cached customers
      try {
        final cached = OfflineService().getCachedCustomers();
        if (cached.isNotEmpty) {
          setState(() {
            _customers = cached
                .map(
                  (e) => {
                    'id': e['id'],
                    'name': e['name'],
                    'phone': e['phone'],
                  },
                )
                .toList();
            _filtered = _customers;
          });
        }
      } catch (e) {
        Logger.warning('Failed to load customers list: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Customer'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (_selectedIndex < _filtered.length - 1) {
                setState(() => _selectedIndex++);
                _scrollSelectedIntoView();
              }
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (_selectedIndex > 0) {
                setState(() => _selectedIndex--);
                _scrollSelectedIntoView();
              }
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              _selectCurrent();
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(context);
            }
          },
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: const InputDecoration(
                  hintText: 'Search customer...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  setState(() {
                    _filtered = _customers
                        .where(
                          (c) => c['name'].toString().toLowerCase().contains(
                            v.toLowerCase(),
                          ),
                        )
                        .toList();
                    _selectedIndex = 0;
                  });
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: _listScrollController,
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final customer = _filtered[index];
                    final isSelected = index == _selectedIndex;
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: Colors.blue.shade50,
                      title: Text(customer['name'] ?? ''),
                      subtitle: Text(customer['phone'] ?? ''),
                      onTap: () {
                        widget.onSelect(customer['id'], customer['name']);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onSelect('', 'WALK-IN CUSTOMER');
            Navigator.pop(context);
          },
          child: const Text('Walk-in Customer'),
        ),
      ],
    );
  }
}
