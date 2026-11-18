import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/daos/nexus_dao.dart';
import '../../data/remote/firestore_service.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_state.dart';
import '../services/notification_service.dart';

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  return AppDatabase.getInstance();
});

final nexusDaoProvider = FutureProvider<NexusDao>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return NexusDao(db);
});

final remoteSyncDataSourceProvider = Provider<RemoteSyncDataSource>((ref) {
  return FirestoreService();
});

final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final dao = await ref.watch(nexusDaoProvider.future);
  final remote = ref.watch(remoteSyncDataSourceProvider);
  return SyncEngine(dao: dao, remote: remote);
});

/// Reactive stream indicating whether the device has network connectivity.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield _hasConnection(initial);

  await for (final results in connectivity.onConnectivityChanged) {
    yield _hasConnection(results);
  }
});

bool _hasConnection(List<ConnectivityResult> results) {
  return results.any((r) => r != ConnectivityResult.none);
}

/// Manages sync state and automatically triggers [SyncEngine.syncAll]
/// whenever connectivity returns.
class SyncController extends Notifier<SyncState> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = false;

  @override
  SyncState build() {
    _listenToConnectivity();
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(refreshQueueCounts);
    return const SyncState();
  }

  void _listenToConnectivity() {
    final connectivity = Connectivity();
    _sub = connectivity.onConnectivityChanged.listen((results) {
      final online = _hasConnection(results);
      if (online && _wasOffline) {
        syncNow();
      }
      _wasOffline = !online;
    });
  }

  Future<void> refreshQueueCounts() async {
    final dao = await ref.read(nexusDaoProvider.future);
    final counts = await dao.getSyncQueueCounts();
    state = state.copyWith(
      pendingCount: counts.pending,
      failedCount: counts.failed,
    );
  }

  Future<SyncRunResult?> syncNow() async {
    if (state.isSyncing) return null;
    state = state.copyWith(isSyncing: true, clearError: true);

    try {
      final engine = await ref.read(syncEngineProvider.future);
      final result = await engine.syncAll();
      final dao = await ref.read(nexusDaoProvider.future);
      final counts = await dao.getSyncQueueCounts();

      state = state.copyWith(
        isSyncing: false,
        pendingCount: counts.pending,
        failedCount: counts.failed,
        lastSyncedAt: DateTime.now(),
        lastError: result.error,
      );
      if (result.failedCount > 0) {
        await NotificationService.instance.showLocalNotification(
          title: 'Sync Failed (${result.failedCount} items)',
          body: result.error ?? 'Tap to open Sync Center and retry.',
          payload: 'sync',
        );
      }
      return result;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return null;
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);
