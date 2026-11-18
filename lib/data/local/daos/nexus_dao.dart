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

  /// Returns a map of `productId -> quantity` for a specific branch.
  Future<Map<String, int>> getBranchStockMap(String branchId) async {
    final rows = await _db.query(
      'branch_stock',
      columns: ['product_id', 'quantity'],
      where: 'branch_id = ? AND is_deleted = 0',
      whereArgs: [branchId],
    );
    return {
      for (final r in rows)
        r['product_id'] as String: (r['quantity'] as num).toInt(),
    };
  }

  /// Adjusts stock for a branch/product and records a [StockMovement] atomically.
  Future<void> adjustBranchStock({
    required String movementId,
    required String branchId,
    required String productId,
    required int delta,
    required String reason,
    required String createdBy,
    String? referenceId,
    String note = '',
    required int timestampMs,
  }) async {
    await _db.transaction((txn) async {
      final stockRows = await txn.query(
        'branch_stock',
        columns: ['quantity'],
        where: 'branch_id = ? AND product_id = ? AND is_deleted = 0',
        whereArgs: [branchId, productId],
        limit: 1,
      );
      final current = stockRows.isEmpty
          ? 0
          : (stockRows.first['quantity'] as num).toInt();
      final nextQty = (current + delta).clamp(0, 1 << 30);

      await txn.insert(
        'branch_stock',
        {
          'id': '${branchId}_$productId',
          'branch_id': branchId,
          'product_id': productId,
          'quantity': nextQty,
          'updated_at': timestampMs,
          'is_deleted': 0,
          'deleted_at': null,
          'sync_status': 'pending',
          'sync_error': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.insert(
        'stock_movements',
        {
          'id': movementId,
          'branch_id': branchId,
          'product_id': productId,
          'change_qty': delta,
          'reason': reason,
          'reference_id': referenceId,
          'note': note,
          'created_by': createdBy,
          'created_at': timestampMs,
          'updated_at': timestampMs,
          'is_deleted': 0,
          'deleted_at': null,
          'sync_status': 'pending',
          'sync_error': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<StockMovement>> getStockMovements({
    String? branchId,
    String? productId,
  }) async {
    final whereParts = <String>['is_deleted = 0'];
    final args = <Object?>[];
    if (branchId != null) {
      whereParts.add('branch_id = ?');
      args.add(branchId);
    }
    if (productId != null) {
      whereParts.add('product_id = ?');
      args.add(productId);
    }
    final rows = await _db.query(
      'stock_movements',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map(StockMovement.fromSqlite).toList();
  }

  /// Executes an inter-branch stock transfer atomically in SQLite.
  Future<void> executeStockTransfer({
    required StockTransfer transfer,
    required String outMovementId,
    required String inMovementId,
  }) async {
    await _db.transaction((txn) async {
      Future<int> readQty(String bId) async {
        final r = await txn.query(
          'branch_stock',
          columns: ['quantity'],
          where: 'branch_id = ? AND product_id = ? AND is_deleted = 0',
          whereArgs: [bId, transfer.productId],
          limit: 1,
        );
        return r.isEmpty ? 0 : (r.first['quantity'] as num).toInt();
      }

      final fromQty = await readQty(transfer.fromBranchId);
      if (fromQty < transfer.quantity) {
        throw StateError('Insufficient stock in source branch ($fromQty available).');
      }
      final toQty = await readQty(transfer.toBranchId);

      Future<void> writeStock(String bId, int qty) async {
        await txn.insert(
          'branch_stock',
          {
            'id': '${bId}_${transfer.productId}',
            'branch_id': bId,
            'product_id': transfer.productId,
            'quantity': qty,
            'updated_at': transfer.updatedAt,
            'is_deleted': 0,
            'deleted_at': null,
            'sync_status': 'pending',
            'sync_error': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await writeStock(transfer.fromBranchId, fromQty - transfer.quantity);
      await writeStock(transfer.toBranchId, toQty + transfer.quantity);

      await txn.insert(
        'stock_transfers',
        transfer.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.insert('stock_movements', {
        'id': outMovementId,
        'branch_id': transfer.fromBranchId,
        'product_id': transfer.productId,
        'change_qty': -transfer.quantity,
        'reason': 'transfer_out',
        'reference_id': transfer.id,
        'note': transfer.note,
        'created_by': transfer.createdBy,
        'created_at': transfer.createdAt,
        'updated_at': transfer.updatedAt,
        'is_deleted': 0,
        'deleted_at': null,
        'sync_status': 'pending',
        'sync_error': null,
      });

      await txn.insert('stock_movements', {
        'id': inMovementId,
        'branch_id': transfer.toBranchId,
        'product_id': transfer.productId,
        'change_qty': transfer.quantity,
        'reason': 'transfer_in',
        'reference_id': transfer.id,
        'note': transfer.note,
        'created_by': transfer.createdBy,
        'created_at': transfer.createdAt,
        'updated_at': transfer.updatedAt,
        'is_deleted': 0,
        'deleted_at': null,
        'sync_status': 'pending',
        'sync_error': null,
      });
    });
  }

  Future<List<StockTransfer>> getStockTransfers() async {
    final rows = await _db.query(
      'stock_transfers',
      where: 'is_deleted = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(StockTransfer.fromSqlite).toList();
  }

  /// Computes total stock units and total sales per branch from local SQLite.
  Future<Map<String, ({int stockUnits, double salesTotal})>>
      getBranchSummaries() async {
    final stockRows = await _db.rawQuery('''
      SELECT branch_id, COALESCE(SUM(quantity), 0) AS total_units
      FROM branch_stock
      WHERE is_deleted = 0
      GROUP BY branch_id
    ''');
    final salesRows = await _db.rawQuery('''
      SELECT branch_id, COALESCE(SUM(total_amount), 0) AS total_sales
      FROM transactions
      WHERE is_deleted = 0 AND type = 'sale'
      GROUP BY branch_id
    ''');

    final stockMap = {
      for (final r in stockRows)
        r['branch_id'] as String: (r['total_units'] as num).toInt(),
    };
    final salesMap = {
      for (final r in salesRows)
        r['branch_id'] as String: (r['total_sales'] as num).toDouble(),
    };

    final keys = {...stockMap.keys, ...salesMap.keys};
    return {
      for (final k in keys)
        k: (stockUnits: stockMap[k] ?? 0, salesTotal: salesMap[k] ?? 0.0),
    };
  }

  /// Atomically records a sale or purchase transaction, updates branch stock,
  /// and inserts stock movement audit rows in SQLite.
  /// Returns a list of `(productId, newQty)` pairs for stock checks.
  Future<List<({String productId, int newQty})>> recordTransactionAtomic({
    required BusinessTransaction transaction,
    required List<({String movementId, String productId, int quantity})> items,
  }) async {
    final updatedStocks = <({String productId, int newQty})>[];

    await _db.transaction((txn) async {
      await txn.insert(
        'transactions',
        transaction.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final item in transaction.items) {
        await txn.insert(
          'transaction_items',
          item.toSqlite(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final isSale = transaction.type == 'sale';
      for (final item in items) {
        final stockRows = await txn.query(
          'branch_stock',
          columns: ['quantity'],
          where: 'branch_id = ? AND product_id = ? AND is_deleted = 0',
          whereArgs: [transaction.branchId, item.productId],
          limit: 1,
        );
        final current = stockRows.isEmpty
            ? 0
            : (stockRows.first['quantity'] as num).toInt();

        if (isSale && current < item.quantity) {
          throw StateError(
            'Insufficient stock for product ${item.productId} ($current available).',
          );
        }

        final delta = isSale ? -item.quantity : item.quantity;
        final nextQty = current + delta;

        await txn.insert(
          'branch_stock',
          {
            'id': '${transaction.branchId}_${item.productId}',
            'branch_id': transaction.branchId,
            'product_id': item.productId,
            'quantity': nextQty,
            'updated_at': transaction.updatedAt,
            'is_deleted': 0,
            'deleted_at': null,
            'sync_status': 'pending',
            'sync_error': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.insert('stock_movements', {
          'id': item.movementId,
          'branch_id': transaction.branchId,
          'product_id': item.productId,
          'change_qty': delta,
          'reason': transaction.type,
          'reference_id': transaction.id,
          'note': transaction.notes,
          'created_by': transaction.createdBy,
          'created_at': transaction.createdAt,
          'updated_at': transaction.updatedAt,
          'is_deleted': 0,
          'deleted_at': null,
          'sync_status': 'pending',
          'sync_error': null,
        });

        updatedStocks.add((productId: item.productId, newQty: nextQty));
      }
    });

    return updatedStocks;
  }
}
