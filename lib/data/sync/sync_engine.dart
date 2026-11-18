import '../local/daos/nexus_dao.dart';
import '../models/syncable_models.dart';
import '../remote/firestore_service.dart';
import 'sync_state.dart';

/// Bi-directional offline-first synchronization engine.
///
/// Conflict Resolution Rules:
/// 1. **Delete Always Wins:** If either local or remote has `isDeleted == true`,
///    the record stays deleted regardless of timestamps.
/// 2. **Last-Write-Wins (LWW):** For non-delete concurrent edits, the record
///    with the greater `updatedAt` timestamp wins.
/// 3. **Idempotency:** Every record uses a client-generated UUID `id` as its
///    Firestore document ID, so retries never create duplicate records.
class SyncEngine {
  SyncEngine({
    required this.dao,
    required this.remote,
  });

  final NexusDao dao;
  final RemoteSyncDataSource remote;

  static const List<String> syncedTables = [
    'branches',
    'products',
    'branch_stock',
    'transactions',
    'stock_movements',
    'stock_transfers',
  ];

  bool _isRunning = false;

  /// Runs a full push-then-pull sync cycle across all synced tables.
  Future<SyncRunResult> syncAll() async {
    if (_isRunning) {
      return const SyncRunResult(pushedCount: 0, pulledCount: 0, failedCount: 0);
    }
    _isRunning = true;
    int pushed = 0;
    int pulled = 0;
    int failed = 0;
    String? firstError;

    try {
      // Pull remote changes first so remote deletes (Delete Always Wins) and
      // newer remote edits (LWW) resolve against local pending rows before push.
      for (final table in syncedTables) {
        pulled += await _pullTable(table);
      }

      for (final table in syncedTables) {
        final pushRes = await _pushTable(table);
        pushed += pushRes.pushed;
        failed += pushRes.failed;
        firstError ??= pushRes.error;
      }
    } catch (e) {
      firstError ??= e.toString();
    } finally {
      _isRunning = false;
    }

    return SyncRunResult(
      pushedCount: pushed,
      pulledCount: pulled,
      failedCount: failed,
      error: firstError,
    );
  }

  /// Pushes all pending/failed/interrupted rows for [table] to Firestore.
  Future<({int pushed, int failed, String? error})> _pushTable(
    String table,
  ) async {
    final rows = await dao.getPendingRows(table);
    int pushed = 0;
    int failed = 0;
    String? firstError;

    for (final row in rows) {
      final id = row['id'] as String;
      try {
        await dao.updateSyncStatus(table: table, id: id, status: 'syncing');

        final payload = await _sqliteRowToFirestore(table, row);
        await remote.upsertDocument(
          collection: table,
          docId: id,
          data: payload,
        );

        await dao.updateSyncStatus(table: table, id: id, status: 'synced');
        pushed++;
      } catch (e) {
        failed++;
        firstError ??= e.toString();
        await dao.updateSyncStatus(
          table: table,
          id: id,
          status: 'failed',
          error: e.toString(),
        );
      }
    }

    return (pushed: pushed, failed: failed, error: firstError);
  }

  /// Pulls remote documents updated since `last_pull_timestamp` and resolves
  /// conflicts using Delete Always Wins + Last-Write-Wins (LWW).
  Future<int> _pullTable(String table) async {
    final lastPull = await dao.getLastPullTimestamp(table);
    final remoteDocs = await remote.fetchUpdatedSince(
      collection: table,
      sinceEpochMs: lastPull,
    );

    if (remoteDocs.isEmpty) return 0;

    int applied = 0;
    int maxUpdatedAt = lastPull;

    for (final doc in remoteDocs) {
      final remoteUpdatedAt = (doc['updatedAt'] as num?)?.toInt() ?? 0;
      if (remoteUpdatedAt > maxUpdatedAt) {
        maxUpdatedAt = remoteUpdatedAt;
      }

      final id = doc['id'] as String;
      final localRow = await dao.getRowById(table, id);
      final resolution = _resolveConflict(localRow: localRow, remoteDoc: doc);

      if (resolution == _ConflictWinner.remote) {
        await _applyRemoteToLocal(table, doc);
        applied++;
      }
    }

    if (maxUpdatedAt > lastPull) {
      await dao.setLastPullTimestamp(table, maxUpdatedAt);
    }

    return applied;
  }

  _ConflictWinner _resolveConflict({
    required Map<String, dynamic>? localRow,
    required Map<String, dynamic> remoteDoc,
  }) {
    if (localRow == null) {
      return _ConflictWinner.remote;
    }

    final localDeleted = (localRow['is_deleted'] as int? ?? 0) == 1;
    final remoteDeleted = (remoteDoc['isDeleted'] as bool?) ?? false;

    // Rule 1: Delete Always Wins no matter what.
    if (remoteDeleted && !localDeleted) {
      // Remote delete overrides any local pending edit.
      return _ConflictWinner.remote;
    }
    if (localDeleted && !remoteDeleted) {
      // Local delete overrides any remote edit; keep local pending to push delete.
      return _ConflictWinner.local;
    }
    if (localDeleted && remoteDeleted) {
      return _ConflictWinner.remote;
    }

    // Rule 2: Last-Write-Wins (LWW) for non-deleted records.
    final localStatus = (localRow['sync_status'] as String?) ?? 'synced';
    final localUpdatedAt = (localRow['updated_at'] as num?)?.toInt() ?? 0;
    final remoteUpdatedAt = (remoteDoc['updatedAt'] as num?)?.toInt() ?? 0;

    if (localStatus == 'synced') {
      return remoteUpdatedAt >= localUpdatedAt
          ? _ConflictWinner.remote
          : _ConflictWinner.local;
    }

    // Local has unsynced pending/failed changes: compare timestamps.
    return remoteUpdatedAt > localUpdatedAt
        ? _ConflictWinner.remote
        : _ConflictWinner.local;
  }

  Future<Map<String, dynamic>> _sqliteRowToFirestore(
    String table,
    Map<String, dynamic> row,
  ) async {
    final base = <String, dynamic>{
      'id': row['id'],
      'updatedAt': row['updated_at'],
      'isDeleted': (row['is_deleted'] as int? ?? 0) == 1,
      'deletedAt': row['deleted_at'],
    };

    switch (table) {
      case 'branches':
        return {
          ...base,
          'name': row['name'],
          'location': row['location'],
          'phone': row['phone'],
          'isActive': (row['is_active'] as int? ?? 1) == 1,
        };
      case 'products':
        return {
          ...base,
          'name': row['name'],
          'sku': row['sku'],
          'barcode': row['barcode'],
          'category': row['category'],
          'costPrice': row['cost_price'],
          'sellingPrice': row['selling_price'],
          'lowStockThreshold': row['low_stock_threshold'],
          'imageUrl': row['image_url'],
        };
      case 'branch_stock':
        return {
          ...base,
          'branchId': row['branch_id'],
          'productId': row['product_id'],
          'quantity': row['quantity'],
        };
      case 'transactions':
        final items = await dao.getTransactionItems(row['id'] as String);
        return {
          ...base,
          'branchId': row['branch_id'],
          'type': row['type'],
          'totalAmount': row['total_amount'],
          'profitAmount': row['profit_amount'],
          'notes': row['notes'],
          'createdBy': row['created_by'],
          'createdAt': row['created_at'],
          'items': items
              .map(
                (i) => {
                  'id': i.id,
                  'transactionId': i.transactionId,
                  'productId': i.productId,
                  'productName': i.productName,
                  'quantity': i.quantity,
                  'unitPrice': i.unitPrice,
                  'unitCost': i.unitCost,
                },
              )
              .toList(),
        };
      case 'stock_movements':
        return {
          ...base,
          'branchId': row['branch_id'],
          'productId': row['product_id'],
          'changeQty': row['change_qty'],
          'reason': row['reason'],
          'referenceId': row['reference_id'],
          'note': row['note'],
          'createdBy': row['created_by'],
          'createdAt': row['created_at'],
        };
      case 'stock_transfers':
        return {
          ...base,
          'fromBranchId': row['from_branch_id'],
          'toBranchId': row['to_branch_id'],
          'productId': row['product_id'],
          'quantity': row['quantity'],
          'status': row['status'],
          'note': row['note'],
          'createdBy': row['created_by'],
          'createdAt': row['created_at'],
        };
      default:
        return base;
    }
  }

  Future<void> _applyRemoteToLocal(
    String table,
    Map<String, dynamic> doc,
  ) async {
    final isDeleted = (doc['isDeleted'] as bool?) == true ? 1 : 0;
    final common = <String, dynamic>{
      'id': doc['id'],
      'updated_at': (doc['updatedAt'] as num).toInt(),
      'is_deleted': isDeleted,
      'deleted_at': (doc['deletedAt'] as num?)?.toInt(),
      'sync_status': 'synced',
      'sync_error': null,
    };

    switch (table) {
      case 'branches':
        await dao.upsertRawRow('branches', {
          ...common,
          'name': doc['name'] ?? '',
          'location': doc['location'] ?? '',
          'phone': doc['phone'] ?? '',
          'is_active': (doc['isActive'] as bool? ?? true) ? 1 : 0,
        });
      case 'products':
        await dao.upsertRawRow('products', {
          ...common,
          'name': doc['name'] ?? '',
          'sku': doc['sku'] ?? '',
          'barcode': doc['barcode'] ?? '',
          'category': doc['category'] ?? 'General',
          'cost_price': (doc['costPrice'] as num? ?? 0).toDouble(),
          'selling_price': (doc['sellingPrice'] as num? ?? 0).toDouble(),
          'low_stock_threshold':
              (doc['lowStockThreshold'] as num? ?? 5).toInt(),
          'image_url': doc['imageUrl'],
        });
      case 'branch_stock':
        await dao.upsertRawRow('branch_stock', {
          ...common,
          'branch_id': doc['branchId'] ?? '',
          'product_id': doc['productId'] ?? '',
          'quantity': (doc['quantity'] as num? ?? 0).toInt(),
        });
      case 'transactions':
        final rawItems = (doc['items'] as List<dynamic>?) ?? const [];
        final items = rawItems
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map(
              (m) => TransactionItemModel(
                id: m['id'] as String,
                transactionId: doc['id'] as String,
                productId: m['productId'] as String,
                productName: m['productName'] as String,
                quantity: (m['quantity'] as num).toInt(),
                unitPrice: (m['unitPrice'] as num).toDouble(),
                unitCost: (m['unitCost'] as num).toDouble(),
              ),
            )
            .toList();
        await dao.saveTransactionWithItems(
          BusinessTransaction(
            id: doc['id'] as String,
            branchId: doc['branchId'] as String? ?? '',
            type: doc['type'] as String? ?? 'sale',
            totalAmount: (doc['totalAmount'] as num? ?? 0).toDouble(),
            profitAmount: (doc['profitAmount'] as num? ?? 0).toDouble(),
            notes: doc['notes'] as String? ?? '',
            createdBy: doc['createdBy'] as String? ?? '',
            createdAt: (doc['createdAt'] as num? ?? doc['updatedAt'] as num)
                .toInt(),
            updatedAt: (doc['updatedAt'] as num).toInt(),
            isDeleted: isDeleted == 1,
            deletedAt: (doc['deletedAt'] as num?)?.toInt(),
            syncStatus: 'synced',
            items: items,
          ),
        );
      case 'stock_movements':
        await dao.upsertRawRow('stock_movements', {
          ...common,
          'branch_id': doc['branchId'] ?? '',
          'product_id': doc['productId'] ?? '',
          'change_qty': (doc['changeQty'] as num? ?? 0).toInt(),
          'reason': doc['reason'] ?? 'adjustment',
          'reference_id': doc['referenceId'],
          'note': doc['note'] ?? '',
          'created_by': doc['createdBy'] ?? '',
          'created_at':
              (doc['createdAt'] as num? ?? doc['updatedAt'] as num).toInt(),
        });
      case 'stock_transfers':
        await dao.upsertRawRow('stock_transfers', {
          ...common,
          'from_branch_id': doc['fromBranchId'] ?? '',
          'to_branch_id': doc['toBranchId'] ?? '',
          'product_id': doc['productId'] ?? '',
          'quantity': (doc['quantity'] as num? ?? 0).toInt(),
          'status': doc['status'] ?? 'completed',
          'note': doc['note'] ?? '',
          'created_by': doc['createdBy'] ?? '',
          'created_at':
              (doc['createdAt'] as num? ?? doc['updatedAt'] as num).toInt(),
        });
    }
  }
}

enum _ConflictWinner { local, remote }
