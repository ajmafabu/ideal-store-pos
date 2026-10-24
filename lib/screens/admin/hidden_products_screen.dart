import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/providers.dart';
import '../../models/product.dart';
import '../../utils/error_messages.dart';

/// Products hidden because they sat at 0 stock with no sale or purchase for
/// 30 days (23 Oct 2026). "Show again" puts one back on the stock lists.
/// They still scan at billing, and any stock change shows them again.
class HiddenProductsScreen extends ConsumerStatefulWidget {
  const HiddenProductsScreen({super.key});

  @override
  ConsumerState<HiddenProductsScreen> createState() => _HiddenProductsScreenState();
}

class _HiddenProductsScreenState extends ConsumerState<HiddenProductsScreen> {
  final _busy = <String>{};

  Future<void> _show(Product p) async {
    setState(() => _busy.add(p.id));
    try {
      await ref.read(productServiceProvider).showProduct(p.id);
      ref.invalidate(productsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${p.name} is back on the stock lists')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.parse(e)), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(productsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden products')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(ErrorMessages.parse(e), textAlign: TextAlign.center),
          ),
        ),
        data: (products) {
          final hidden = products.where((p) => p.isHidden).toList()..sort((a, b) => b.hiddenAt!.compareTo(a.hiddenAt!));
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Products at 0 stock with no sale and no purchase for 30 days are hidden from the stock lists '
                  'by themselves. They still scan at billing, and come back as soon as you enter a purchase. '
                  'Tap Show again to bring one back now.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              if (hidden.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No hidden products')),
                )
              else
                for (final p in hidden)
                  ListTile(
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [
                        if ((p.tamilName ?? '').isNotEmpty) p.tamilName!,
                        'hidden ${DateFormat('d MMM').format(p.hiddenAt!.toLocal())}',
                        if ((p.category ?? '').isNotEmpty) p.category!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _busy.contains(p.id)
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : OutlinedButton(onPressed: () => _show(p), child: const Text('Show again')),
                  ),
            ],
          );
        },
      ),
    );
  }
}
