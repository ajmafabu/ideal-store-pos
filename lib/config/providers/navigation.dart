import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================
// NAVIGATION
// ============================================

class CurrentTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) => state = index;
}

final currentTabProvider = NotifierProvider<CurrentTabNotifier, int>(
  CurrentTabNotifier.new,
);
