/// Represents the current state of the bi-directional sync engine.
class SyncState {
  const SyncState({
    this.isSyncing = false,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final bool isSyncing;
  final int pendingCount;
  final int failedCount;
  final DateTime? lastSyncedAt;
  final String? lastError;

  SyncState copyWith({
    bool? isSyncing,
    int? pendingCount,
    int? failedCount,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Summary returned after a sync cycle completes.
class SyncRunResult {
  const SyncRunResult({
    required this.pushedCount,
    required this.pulledCount,
    required this.failedCount,
    this.error,
  });

  final int pushedCount;
  final int pulledCount;
  final int failedCount;
  final String? error;
}
