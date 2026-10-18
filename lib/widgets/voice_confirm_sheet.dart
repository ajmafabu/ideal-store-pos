import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/product_search.dart';
import '../utils/qty_format.dart';
import '../utils/voice_billing.dart';
import '../utils/voice_parser.dart';

/// What the shop confirmed for one spoken item.
class VoicePick {
  VoicePick({required this.line, required this.product, required this.qty});
  final VoiceLine line;
  final Product product;
  final double qty;

  /// The shop chose something other than the first guess, or confirmed a
  /// guess the app was unsure of: worth remembering.
  bool get worthRemembering => !line.isSure || line.best?.product.id != product.id;
}

/// After speaking: every heard item with its best match, other choices to
/// tap, and the quantity. Nothing goes on the bill until "Add".
/// (Before 16 Oct 2026 voice added its first guess straight to the bill.)
class VoiceConfirmSheet extends StatefulWidget {
  const VoiceConfirmSheet({
    super.key,
    required this.heard,
    required this.lines,
    required this.tamil,
    required this.products,
    required this.reparse,
    required this.rememberWords,
  });

  final String heard;
  final List<VoiceLine> lines;
  final bool tamil;

  /// For "search" on a line (the phone mis-heard the name).
  final List<Product> products;

  /// Reads corrected text again (the heard text was edited).
  final List<VoiceLine> Function(String text) reparse;

  /// Saves words the phone mis-heard ("குரு" → "bru") for next time.
  final Future<void> Function(Map<String, String> words) rememberWords;

  static Future<List<VoicePick>?> show(
    BuildContext context, {
    required String heard,
    required List<VoiceLine> lines,
    required bool tamil,
    required List<Product> products,
    required List<VoiceLine> Function(String text) reparse,
    required Future<void> Function(Map<String, String> words) rememberWords,
  }) {
    return showModalBottomSheet<List<VoicePick>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VoiceConfirmSheet(
        heard: heard,
        lines: lines,
        tamil: tamil,
        products: products,
        reparse: reparse,
        rememberWords: rememberWords,
      ),
    );
  }

  @override
  State<VoiceConfirmSheet> createState() => _VoiceConfirmSheetState();
}

class _LineState {
  _LineState(this.line)
      : chosen = line.best,
        qty = line.best?.qty ?? 1,
        // a weak guess starts unticked: the shop taps the right choice
        include = line.best != null && line.best!.score >= 0.7;
  final VoiceLine line;
  VoiceChoice? chosen;
  double qty;
  bool include;
}

class _VoiceConfirmSheetState extends State<VoiceConfirmSheet> {
  late List<_LineState> _lines = [for (final l in widget.lines) _LineState(l)];
  late String _heard = widget.heard;

  bool get _ta => widget.tamil;

  bool _loose(Product p) =>
      const {'kg', 'g', 'gm', 'gram', 'ltr', 'litre', 'l', 'ml'}.contains(p.unit.toLowerCase().trim());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _lines.where((l) => l.include && l.chosen != null).length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.mic, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ta ? 'சரிபார்த்து சேர்க்கவும்' : 'Check and add',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => showVoiceWordsDialog(context, tamil: _ta),
                  icon: const Icon(Icons.menu_book, size: 18),
                  label: Text(_ta ? 'சொற்கள்' : 'Words'),
                ),
                IconButton(
                  tooltip: _ta ? 'மூடு' : 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // what the phone heard: tap to correct a mis-heard word
          InkWell(
            onTap: _editHeard,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '“$_heard”',
                      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit, size: 18, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text(_ta ? 'திருத்து' : 'Correct', style: TextStyle(color: scheme.primary, fontSize: 13)),
                ],
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: _lines.length,
              itemBuilder: (_, i) => _lineCard(_lines[i], scheme),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: Text(_ta ? 'ரத்து' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: count == 0 ? null : _add,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: Text(
                        _ta ? '$count பொருள் சேர்' : 'Add $count item${count == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineCard(_LineState s, ColorScheme scheme) {
    final line = s.line;
    final chosen = s.chosen;
    final unsure = chosen != null && (!line.isSure || chosen.product.id != line.best?.product.id) && s.include;
    final borderColor = chosen == null
        ? scheme.outlineVariant
        : !s.include
            ? scheme.outlineVariant
            : line.isSure
                ? Colors.green
                : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: s.include && chosen != null,
                  onChanged: chosen == null ? null : (v) => setState(() => s.include = v ?? false),
                ),
                Expanded(
                  child: Text(
                    '“${line.spoken}”',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ),
                if (chosen != null && !line.isSure)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _ta ? 'சரிபார்க்கவும்' : 'Check',
                      style: const TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            if (chosen == null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _ta ? 'பொருள் கிடைக்கவில்லை' : 'Not found',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                    _searchButton(s),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chosen.product.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          if ((chosen.product.tamilName ?? '').isNotEmpty)
                            Text(chosen.product.tamilName!, style: const TextStyle(fontSize: 13)),
                          Text(
                            '₹${chosen.product.sellingPrice.toStringAsFixed(2)} / ${chosen.product.unit}'
                            '${chosen.product.stock < s.qty ? (_ta ? '  •  இருப்பு ${formatQty(chosen.product.stock)}' : '  •  stock ${formatQty(chosen.product.stock)}') : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: chosen.product.stock < s.qty ? scheme.error : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _qtyStepper(s),
                  ],
                ),
              ),
              if (chosen.note != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Text(
                    chosen.note!,
                    style: TextStyle(fontSize: 12, color: chosen.needsCheck ? Colors.deepOrange : scheme.primary),
                  ),
                ),
              Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // a product picked from search shows as a choice too
                      if (!line.choices.any((c) => c.product.id == chosen.product.id))
                        ChoiceChip(
                          label: Text(
                            '${chosen.product.name}  ₹${chosen.product.sellingPrice.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: true,
                          onSelected: (_) {},
                        ),
                      for (final c in line.choices.take(unsure || !line.isSure || line.choices.length > 1 ? 5 : 0))
                        ChoiceChip(
                          label: Text(
                            '${c.product.name}  ₹${c.product.sellingPrice.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: c.product.id == chosen.product.id,
                          onSelected: (_) => setState(() {
                            s.chosen = c;
                            s.qty = c.qty;
                            s.include = true;
                          }),
                        ),
                      _searchButton(s),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchButton(_LineState s) {
    return ActionChip(
      avatar: const Icon(Icons.search, size: 18),
      label: Text(_ta ? 'தேடு' : 'Search', style: const TextStyle(fontSize: 12)),
      onPressed: () => _search(s),
    );
  }

  /// Pick any product by typing (the phone heard the name wrong).
  Future<void> _search(_LineState s) async {
    final controller = TextEditingController();
    final picked = await showDialog<Product>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final results = searchProducts(widget.products, controller.text).take(30).toList();
          return AlertDialog(
            title: Text(_ta ? 'பொருள் தேடு' : 'Find product'),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _ta ? 'பெயர் அல்லது பார்கோடு' : 'Name or barcode',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final p = results[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.name),
                          subtitle: (p.tamilName ?? '').isEmpty ? null : Text(p.tamilName!),
                          trailing: Text('₹${p.sellingPrice.toStringAsFixed(2)}'),
                          onTap: () => Navigator.pop(ctx, p),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_ta ? 'ரத்து' : 'Cancel')),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (picked == null || !mounted) return;
    setState(() {
      final keepQty = s.chosen == null ? 1.0 : s.qty;
      s.chosen = VoiceChoice(product: picked, qty: keepQty, score: 1);
      s.qty = _loose(picked) ? keepQty : keepQty.roundToDouble().clamp(1, 99999).toDouble();
      s.include = true;
    });
  }

  /// Correct what the phone heard, then read it again.
  Future<void> _editHeard() async {
    final controller = TextEditingController(text: _heard);
    var remember = true;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_ta ? 'கேட்டதை திருத்து' : 'Correct what was heard'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(
                  helperText: _ta ? 'பொருட்களை , கொண்டு பிரிக்கவும்' : 'Separate items with a comma',
                  border: const OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: remember,
                onChanged: (v) => setLocal(() => remember = v ?? true),
                title: Text(
                  _ta ? 'திருத்திய சொற்களை நினைவில் வை' : 'Remember the words I fixed',
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  _ta ? 'அடுத்த முறை தானாக சரியாகும்' : 'Next time they are fixed by themselves',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_ta ? 'ரத்து' : 'Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(_ta ? 'மீண்டும் சரிபார்' : 'Check again'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final before = _heard;
    setState(() {
      _heard = text.trim();
      _lines = [for (final l in widget.reparse(_heard)) _LineState(l)];
    });
    if (!remember) return;
    final fixed = VoiceParser.correctionsBetween(before, _heard);
    if (fixed.isEmpty) return;
    await widget.rememberWords(fixed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_ta ? 'நினைவில் வைத்தது' : 'Remembered'}: '
          '${fixed.entries.map((e) => '${e.key} → ${e.value}').join(', ')}',
        ),
      ),
    );
  }

  Widget _qtyStepper(_LineState s) {
    final loose = _loose(s.chosen!.product);
    final step = loose ? 0.25 : 1.0;
    final minQty = loose ? 0.25 : 1.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: _ta ? 'குறை' : 'Less',
          icon: const Icon(Icons.remove),
          onPressed: s.qty <= minQty ? null : () => setState(() => s.qty = (s.qty - step).clamp(minQty, 9999)),
        ),
        InkWell(
          onTap: () => _typeQty(s, loose),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            alignment: Alignment.center,
            child: Text(formatQty(s.qty), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        IconButton.filledTonal(
          tooltip: _ta ? 'கூட்டு' : 'More',
          icon: const Icon(Icons.add),
          onPressed: () => setState(() => s.qty += step),
        ),
      ],
    );
  }

  Future<void> _typeQty(_LineState s, bool loose) async {
    final c = TextEditingController(text: formatQty(s.qty));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_ta ? 'அளவு' : 'Quantity'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: loose),
          onSubmitted: (t) => Navigator.pop(ctx, double.tryParse(t)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_ta ? 'ரத்து' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)), child: const Text('OK')),
        ],
      ),
    );
    if (v == null || v <= 0) return;
    // pieces and packs are whole numbers
    setState(() => s.qty = loose ? v : v.roundToDouble().clamp(1, 99999));
  }

  void _add() {
    Navigator.pop(context, [
      for (final s in _lines)
        if (s.include && s.chosen != null) VoicePick(line: s.line, product: s.chosen!.product, qty: s.qty),
    ]);
  }
}

/// The taught words ("குரு" → "bru"): see them, add one, or delete one.
Future<void> showVoiceWordsDialog(BuildContext context, {required bool tamil}) async {
  var words = await VoiceWords.load();
  if (!context.mounted) return;
  final heardCtl = TextEditingController();
  final meantCtl = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> add() async {
          final heard = heardCtl.text.trim();
          final meant = meantCtl.text.trim();
          if (heard.isEmpty || meant.isEmpty) return;
          await VoiceWords.add({heard: meant});
          words = await VoiceWords.load();
          heardCtl.clear();
          meantCtl.clear();
          setLocal(() {});
        }

        final entries = words.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        return AlertDialog(
          title: Text(tamil ? 'குரல் சொற்கள்' : 'Voice words'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tamil
                      ? 'போன் தவறாக கேட்கும் சொல் → சரியான சொல்'
                      : 'Word the phone hears wrong → the right word',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: heardCtl,
                        decoration: InputDecoration(
                          labelText: tamil ? 'கேட்பது (குரு)' : 'Heard (குரு)',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('→')),
                    Expanded(
                      child: TextField(
                        controller: meantCtl,
                        decoration: InputDecoration(
                          labelText: tamil ? 'சரி (bru)' : 'Means (bru)',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => add(),
                      ),
                    ),
                    IconButton(
                      tooltip: tamil ? 'சேர்' : 'Add',
                      icon: const Icon(Icons.add_circle),
                      onPressed: add,
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(
                            tamil
                                ? 'இன்னும் இல்லை. "திருத்து" செய்து "நினைவில் வை" டிக் செய்தால் இங்கே வரும்.'
                                : 'None yet. Fix a heard text with "Remember" ticked and it appears here.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(
                          children: [
                            for (final e in entries)
                              ListTile(
                                dense: true,
                                title: Text('${e.key}  →  ${e.value}'),
                                trailing: IconButton(
                                  tooltip: tamil ? 'நீக்கு' : 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    words.remove(e.key);
                                    await VoiceWords.save(words);
                                    setLocal(() {});
                                  },
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tamil ? 'மூடு' : 'Close')),
          ],
        );
      },
    ),
  );
  heardCtl.dispose();
  meantCtl.dispose();
}
