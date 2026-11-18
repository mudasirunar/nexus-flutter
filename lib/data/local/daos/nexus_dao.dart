import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../../models/syncable_models.dart';

/// Data Access Object for all local SQLite tables and sync queue operations.
class NexusDao {
  NexusDao(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  // ---------------------------------------------------------------------------
  // Users (Local RBAC cache)
  // ---------------------------------------------------------------------------

  Future<void> upsertUser(UserProfile user) async {
    await _db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserProfile?> getUser(String uid) async {
    final rows = await _db.query(
      'users',
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserProfile.fromMap(rows.first);
  }

  // ---------------------------------------------------------------------------
  // Generic Sync Queue & Metadata Helpers
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getPendingRows(String table) async {
    return _db.query(
      table,
      where: "sync_status IN ('pending', 'failed', 'syncing')",
      orderBy: 'updated_at ASC',
    );
  }

  Future<Map<String, dynamic>?> getRowById(String table, String id) async {
    final rows = await _db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateSyncStatus({
    required String table,
    required String id,
    required String status,
    String? error,
  }) async {
    await _db.update(
      table,
      {'sync_status': status, 'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertRawRow(String table, Map<String, dynamic> row) async {
    await _db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getLastPullTimestamp(String collection) async {
    final rows = await _db.query(
      'sync_metadata',
      where: 'key = ?',
      whereArgs: ['last_pull_$collection'],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String) ?? 0;
  }

  Future<void> setLastPullTimestamp(String collection, int epochMs) async {
    await _db.insert(
      'sync_metadata',
      {'key': 'last_pull_$collection', 'value': epochMs.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({int pending, int failed})> getSyncQueueCounts() async {
    const tables = [
      'branches',
      'products',
      'branch_stock',
      'transactions',
      'stock_movements',
      'stock_transfers',
    ];
    int pending = 0;
    int failed = 0;
    for (final table in tables) {
      final pCount = Sqflite.firstIntValue(
            await _db.rawQuery(
              "SELECT COUNT(*) FROM $table WHERE sync_status IN ('pending', 'syncing')",
            ),
          ) ??
          0;
      final fCount = Sqflite.firstIntValue(
            await _db.rawQuery(
              "SELECT COUNT(*) FROM $table WHERE sync_status = 'failed'",
            ),
          ) ??
          0;
      pending += pCount;
      failed += fCount;
    }
    return (pending: pending, failed: failed);
  }

  // ---------------------------------------------------------------------------
  // Entity Reads & Writes
  // ---------------------------------------------------------------------------

  Future<List<Branch>> getBranches({bool includeDeleted = false}) async {
    final rows = await _db.query(
      'branches',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return rows.map(Branch.fromSqlite).toList();
  }

  Future<void> saveBranch(Branch branch) =>
      upsertRawRow('branches', branch.toSqlite());

  Future<List<Product>> getProducts({bool includeDeleted = false}) async {
    final rows = await _db.query(
      'products',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromSqlite).toList();
  }

  Future<void> saveProduct(Product product) =>
      upsertRawRow('products', product.toSqlite());

  Future<int> getBranchStockQty(String branchId, String productId) async {
    final rows = await _db.query(
      'branch_stock',
      columns: ['quantity'],
      where: 'branch_id = ? AND product_id = ? AND is_deleted = 0',
      whereArgs: [branchId, productId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['quantity'] as num).toInt();
  }

  Future<void> setBranchStock({
    required String branchId,
    required String productId,
    required int quantity,
    required int updatedAt,
    String syncStatus = 'pending',
  }) async {
    final id = '${branchId}_$productId';
    await upsertRawRow('branch_stock', {
      'id': id,
      'branch_id': branchId,
      'product_id': productId,
      'quantity': quantity,
      'updated_at': updatedAt,
      'is_deleted': 0,
      'deleted_at': null,
      'sync_status': syncStatus,
      'sync_error': null,
    });
  }

  Future<List<TransactionItemModel>> getTransactionItems(
    String transactionId,
  ) async {
    final rows = await _db.query(
      'transaction_items',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
    return rows.map(TransactionItemModel.fromSqlite).toList();
  }

  Future<void> saveTransactionWithItems(BusinessTransaction tx) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'transactions',
        tx.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'transaction_items',
        where: 'transaction_id = ?',
        whereArgs: [tx.id],
      );
      for (final item in tx.items) {
        await txn.insert(
          'transaction_items',
          item.toSqlite(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<BusinessTransaction>> getTransactions({
    String? branchId,
    bool includeDeleted = false,
  }) async {
    final whereParts = <String>[];
    final whereArgs = <Object?>[];

    if (!includeDeleted) {
      whereParts.add('is_deleted = 0');
    }
    if (branchId != null) {
      whereParts.add('branch_id = ?');
      whereArgs.add(branchId);
    }

    final rows = await _db.query(
      'transactions',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );

    final result = <BusinessTransaction>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final items = await getTransactionItems(id);
      result.add(BusinessTransaction.fromSqlite(row, items: items));
    }
    return result;
  }

  /// Marks any local syncable record as deleted (Delete Always Wins).
  Future<void> softDeleteRecord({
    required String table,
    required String id,
    required int deletedAt,
  }) async {
    await _db.update(
      table,
      {
        'is_deleted': 1,
        'deleted_at': deletedAt,
        'updated_at': deletedAt,
        'sync_status': 'pending',
        'sync_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
