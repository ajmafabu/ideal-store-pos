import 'package:flutter/material.dart';

/// Pick one item from a long list (1,000+ products, every supplier) by
/// typing: a tall sheet with a search box on top, results A → Z, and the
/// list kept above the keyboard.
///
/// QA test 8 Oct 2026: plain dropdowns with no search (findings 30, 57),
/// lists sorted Z → A (12), one result row visible under the keyboard (17).
Future<T?> showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) label,
  String Function(T)? subtitle,
  String Function(T)? searchText,
  String hint = 'Type to search',
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _SearchPickerSheet<T>(
      title: title,
      items: items,
      label: label,
      subtitle: subtitle,
      searchText: searchText,
      hint: hint,
    ),
  );
}

class _SearchPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) label;
  final String Function(T)? subtitle;
  final String Function(T)? searchText;
  final String hint;

  const _SearchPickerSheet({
    required this.title,
    required this.items,
    required this.label,
    this.subtitle,
    this.searchText,
    required this.hint,
  });

  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  final _search = TextEditingController();
  late final List<T> _sorted;
  late List<T> _shown;

  @override
  void initState() {
    super.initState();
    _sorted = List.of(widget.items)
      ..sort((a, b) => widget.label(a).toLowerCase().compareTo(widget.label(b).toLowerCase()));
    _shown = _sorted;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter(String q) {
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    setState(() {
      _shown = words.isEmpty
          ? _sorted
          : _sorted.where((item) {
              final text = '${widget.label(item)} ${widget.searchText?.call(item) ?? ''}'.toLowerCase();
              return words.every(text.contains);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.85 - media.viewInsets.bottom * 0.5,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: _filter,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_shown.length} of ${_sorted.length}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ),
            Expanded(
              child: _shown.isEmpty
                  ? const Center(child: Text('Nothing matches'))
                  : ListView.separated(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = _shown[i];
                        final sub = widget.subtitle?.call(item);
                        return ListTile(
                          minTileHeight: 56,
                          title: Text(widget.label(item)),
                          subtitle: sub == null || sub.isEmpty ? null : Text(sub),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
