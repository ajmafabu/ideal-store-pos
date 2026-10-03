import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services.dart';

// ============================================
// SYNC / CONNECTIVITY
// ============================================

final forceSyncProvider = FutureProvider<bool>((ref) async {
  final offlineService = ref.watch(offlineServiceProvider);
  return await offlineService.forceSync();
});

// Periodically refreshes pending sync count (every 10 seconds)
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final offlineService = ref.watch(offlineServiceProvider);

  while (true) {
    final pendingSales = offlineService.pendingCount;
    final pendingOps = offlineService.pendingOpsCount;
    final pendingWrites = offlineService.pendingWritesCount;
    // Use actual Supabase reachability, not just basic network connectivity
    final isConnected = await offlineService.isOnline();

    yield SyncStatus(
      isConnected: isConnected,
      pendingSales: pendingSales,
      pendingOps: pendingOps,
      pendingWrites: pendingWrites,
      lastSyncError: offlineService.lastSyncError,
      needsReview: offlineService.deadLetterCount,
    );

    await Future.delayed(const Duration(seconds: 10));
  }
});

class SyncStatus {
  final bool isConnected;
  final int pendingSales;
  final int pendingOps;
  final int pendingWrites;
  final String? lastSyncError;

  /// Items the server refused 5 times, kept for review (#6).
  final int needsReview;

  const SyncStatus({
    required this.isConnected,
    required this.pendingSales,
    required this.pendingOps,
    required this.pendingWrites,
    this.lastSyncError,
    this.needsReview = 0,
  });

  int get totalPending => pendingSales + pendingOps + pendingWrites;
  bool get hasPending => totalPending > 0;
}
