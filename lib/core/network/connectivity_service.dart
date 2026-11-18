import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
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

/// Manages bi-directional sync state, live Firestore `.snapshots()` listeners,
/// and automatic sync on connectivity restoration.
class SyncController extends Notifier<SyncState> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final List<StreamSubscription<List<Map<String, dynamic>>>> _snapshotSubs = [];
  bool _wasOffline = false;
  bool _listenersActive = false;

  @override
  SyncState build() {
    _listenToConnectivity();
    ref.onDispose(() {
      _connectivitySub?.cancel();
      stopRealtimeListeners();
    });
    Future.microtask(refreshQueueCounts);
    return const SyncState();
  }

  void _listenToConnectivity() {
    final connectivity = Connectivity();
    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      final online = _hasConnection(results);
      if (online && _wasOffline) {
        syncNow();
        if (_listenersActive) {
          startRealtimeListeners();
        }
      }
      _wasOffline = !online;
    });
  }

  /// Attaches live Firestore `.snapshots()` listeners across all synced tables
  /// so remote changes from other devices appear in SQLite & UI immediately.
  Future<void> startRealtimeListeners() async {
    await stopRealtimeListeners();
    _listenersActive = true;

    final dao = await ref.read(nexusDaoProvider.future);
    final engine = await ref.read(syncEngineProvider.future);
    final remote = ref.read(remoteSyncDataSourceProvider);

    for (final table in SyncEngine.syncedTables) {
      final since = await dao.getLastPullTimestamp(table);
      final sub = remote
          .watchUpdatedSince(collection: table, sinceEpochMs: since)
          .listen(
        (docs) async {
          if (docs.isEmpty) return;
          final applied = await engine.applyRemoteBatch(table, docs);
          if (applied > 0) {
            final counts = await dao.getSyncQueueCounts();
            state = state.copyWith(
              dataVersion: state.dataVersion + 1,
              pendingCount: counts.pending,
              failedCount: counts.failed,
              lastSyncedAt: DateTime.now(),
            );
          }
        },
        onError: (Object e) {
          debugPrint('Realtime listener ($table) error: $e');
        },
      );
      _snapshotSubs.add(sub);
    }
  }

  Future<void> stopRealtimeListeners() async {
    _listenersActive = false;
    for (final sub in _snapshotSubs) {
      await sub.cancel();
    }
    _snapshotSubs.clear();
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
        dataVersion:
            result.pulledCount > 0 ? state.dataVersion + 1 : state.dataVersion,
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
