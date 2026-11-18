import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/data/local/app_database.dart';
import 'package:nexus/data/local/daos/nexus_dao.dart';
import 'package:nexus/data/models/syncable_models.dart';
import 'package:nexus/data/remote/firestore_service.dart';
import 'package:nexus/data/sync/sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeRemoteSyncDataSource implements RemoteSyncDataSource {
  final Map<String, Map<String, Map<String, dynamic>>> store = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers =
      {};
  int upsertCallCount = 0;
  int? failAfterUpserts;

  @override
  Future<void> upsertDocument({
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    upsertCallCount++;
    if (failAfterUpserts != null && upsertCallCount > failAfterUpserts!) {
      throw Exception('Simulated network drop mid-sync');
    }
    store.putIfAbsent(collection, () => {});
    store[collection]![docId] = Map<String, dynamic>.from(data);
    _controllers[collection]?.add(store[collection]!.values.toList());
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUpdatedSince({
    required String collection,
    required int sinceEpochMs,
  }) async {
    final docs = store[collection]?.values ?? const [];
    return docs
        .where((d) => ((d['updatedAt'] as num?)?.toInt() ?? 0) > sinceEpochMs)
        .map((d) => Map<String, dynamic>.from(d))
        .toList()
      ..sort(
        (a, b) =>
            (a['updatedAt'] as int).compareTo(b['updatedAt'] as int),
      );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchUpdatedSince({
    required String collection,
    required int sinceEpochMs,
  }) {
    final ctrl = _controllers.putIfAbsent(
      collection,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
    return ctrl.stream.map(
      (docs) => docs
          .where((d) => ((d['updatedAt'] as num?)?.toInt() ?? 0) > sinceEpochMs)
          .map((d) => Map<String, dynamic>.from(d))
          .toList(),
    );
  }
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late AppDatabase appDb;
  late NexusDao dao;
  late FakeRemoteSyncDataSource remote;
  late SyncEngine engine;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => AppDatabase.createSchema(db),
      ),
    );
    appDb = AppDatabase.forTesting(db);
    dao = NexusDao(appDb);
    remote = FakeRemoteSyncDataSource();
    engine = SyncEngine(dao: dao, remote: remote);
  });

  tearDown(() async {
    await appDb.close();
  });

  BusinessTransaction makeSale(String id, int ts) {
    return BusinessTransaction(
      id: id,
      branchId: 'branch-1',
      type: 'sale',
      totalAmount: 100.0,
      profitAmount: 25.0,
      createdBy: 'user-1',
      createdAt: ts,
      updatedAt: ts,
      syncStatus: 'pending',
      items: [
        TransactionItemModel(
          id: 'item-$id',
          transactionId: id,
          productId: 'prod-1',
          productName: 'Widget',
          quantity: 2,
          unitPrice: 50.0,
          unitCost: 37.5,
        ),
      ],
    );
  }

  test('1. 10 offline sales sync to remote exactly once', () async {
    for (int i = 1; i <= 10; i++) {
      await dao.saveTransactionWithItems(makeSale('tx-$i', 1000 + i));
    }

    final result = await engine.syncAll();

    expect(result.pushedCount, 10);
    expect(result.failedCount, 0);
    expect(remote.store['transactions']?.length, 10);

    final localTxs = await dao.getTransactions();
    expect(localTxs.length, 10);
    expect(localTxs.every((t) => t.syncStatus == 'synced'), isTrue);
  });

  test('2. Retrying the same transaction never creates a duplicate', () async {
    final tx = makeSale('tx-idem-1', 2000);
    await dao.saveTransactionWithItems(tx);

    await engine.syncAll();
    expect(remote.store['transactions']?.length, 1);

    // Force retry of the same transaction ID.
    await dao.updateSyncStatus(
      table: 'transactions',
      id: 'tx-idem-1',
      status: 'failed',
      error: 'Manual retry test',
    );
    await engine.syncAll();

    expect(remote.store['transactions']?.length, 1);
    expect(remote.store['transactions']!['tx-idem-1']!['totalAmount'], 100.0);
  });

  test('3. Last-Write-Wins resolves non-delete conflicts by updatedAt', () async {
    // Local product has pending edit at t=2000.
    await dao.saveProduct(
      const Product(
        id: 'prod-1',
        name: 'Local Older Name',
        sku: 'SKU-1',
        costPrice: 10,
        sellingPrice: 20,
        updatedAt: 2000,
        syncStatus: 'pending',
      ),
    );

    // Remote has newer edit at t=3000.
    remote.store['products'] = {
      'prod-1': {
        'id': 'prod-1',
        'name': 'Remote Newer Name',
        'sku': 'SKU-1',
        'barcode': '',
        'category': 'General',
        'costPrice': 10.0,
        'sellingPrice': 25.0,
        'lowStockThreshold': 5,
        'updatedAt': 3000,
        'isDeleted': false,
        'deletedAt': null,
      },
    };

    // Pull first (or syncAll where remote wins on pull if we test pull; note
    // syncAll pushes first then pulls, so to simulate concurrent remote newer
    // edit arriving after local was edited offline, test remote winning on pull
    // when local pending is older):
    await dao.saveProduct(
      const Product(
        id: 'prod-2',
        name: 'Local Newer Name',
        sku: 'SKU-2',
        costPrice: 10,
        sellingPrice: 30,
        updatedAt: 5000,
        syncStatus: 'pending',
      ),
    );
    remote.store['products']!['prod-2'] = {
      'id': 'prod-2',
      'name': 'Remote Older Name',
      'sku': 'SKU-2',
      'costPrice': 10.0,
      'sellingPrice': 15.0,
      'updatedAt': 1000,
      'isDeleted': false,
    };

    await engine.syncAll();
    final products = await dao.getProducts();
    final p2 = products.firstWhere((p) => p.id == 'prod-2');
    expect(p2.name, 'Local Newer Name');
    expect(remote.store['products']!['prod-2']!['name'], 'Local Newer Name');
  });

  test('4a. Delete Always Wins: local delete beats newer remote update', () async {
    await dao.saveProduct(
      const Product(
        id: 'prod-del-local',
        name: 'Deleted Locally',
        sku: 'SKU-DEL-1',
        costPrice: 10,
        sellingPrice: 20,
        updatedAt: 1000,
        isDeleted: true,
        deletedAt: 1000,
        syncStatus: 'pending',
      ),
    );

    // Remote has a much newer non-delete update at t=9999.
    remote.store['products'] = {
      'prod-del-local': {
        'id': 'prod-del-local',
        'name': 'Updated Remotely Later',
        'sku': 'SKU-DEL-1',
        'costPrice': 10.0,
        'sellingPrice': 99.0,
        'updatedAt': 9999,
        'isDeleted': false,
        'deletedAt': null,
      },
    };

    await engine.syncAll();

    // Must remain deleted both locally and on remote.
    final activeProducts = await dao.getProducts(includeDeleted: false);
    expect(activeProducts.any((p) => p.id == 'prod-del-local'), isFalse);
    expect(remote.store['products']!['prod-del-local']!['isDeleted'], isTrue);
  });

  test('4b. Delete Always Wins: remote delete beats newer local pending edit', () async {
    await dao.saveProduct(
      const Product(
        id: 'prod-del-remote',
        name: 'Edited Locally Later',
        sku: 'SKU-DEL-2',
        costPrice: 10,
        sellingPrice: 50,
        updatedAt: 9999,
        isDeleted: false,
        syncStatus: 'pending',
      ),
    );

    // Simulate remote already deleted at t=1000 (even if older timestamp!).
    remote.store['products'] = {
      'prod-del-remote': {
        'id': 'prod-del-remote',
        'name': 'Deleted Remotely',
        'sku': 'SKU-DEL-2',
        'costPrice': 10.0,
        'sellingPrice': 20.0,
        'updatedAt': 1000,
        'isDeleted': true,
        'deletedAt': 1000,
      },
    };

    // Pull remote state directly by having remote pull run, or test full sync
    // where remote delete is pulled before push:
    // Note: In a real multi-device scenario, pull or listener receives the
    // remote delete; here we verify that once pulled, local is deleted and
    // never resurrected.
    await dao.upsertRawRow('products', {
      'id': 'prod-del-remote',
      'name': 'Edited Locally Later',
      'sku': 'SKU-DEL-2',
      'barcode': '',
      'category': 'General',
      'cost_price': 10.0,
      'selling_price': 50.0,
      'low_stock_threshold': 5,
      'image_url': null,
      'updated_at': 9999,
      'is_deleted': 0,
      'deleted_at': null,
      'sync_status': 'pending',
      'sync_error': null,
    });

    await engine.syncAll();

    // Must remain deleted locally AND on remote (never resurrected).
    final active = await dao.getProducts(includeDeleted: false);
    expect(active.any((p) => p.id == 'prod-del-remote'), isFalse);
    expect(
      remote.store['products']!['prod-del-remote']!['isDeleted'],
      isTrue,
    );
  });

  test('5. Interrupted sync recovers cleanly without losing or duplicating', () async {
    for (int i = 1; i <= 5; i++) {
      await dao.saveTransactionWithItems(makeSale('tx-int-$i', 3000 + i));
    }

    // Fail after 2 successful upserts.
    remote.failAfterUpserts = 2;
    final firstRun = await engine.syncAll();

    expect(firstRun.pushedCount, 2);
    expect(firstRun.failedCount, 3);
    expect(remote.store['transactions']?.length, 2);

    // Network recovers.
    remote.failAfterUpserts = null;
    final secondRun = await engine.syncAll();

    expect(secondRun.pushedCount, 3);
    expect(secondRun.failedCount, 0);
    expect(remote.store['transactions']?.length, 5);

    final allLocal = await dao.getTransactions();
    expect(allLocal.length, 5);
    expect(allLocal.every((t) => t.syncStatus == 'synced'), isTrue);
  });

  test('6. Realtime snapshot stream applies remote updates to local SQLite', () async {
    final sub = remote
        .watchUpdatedSince(collection: 'products', sinceEpochMs: 0)
        .listen((docs) => engine.applyRemoteBatch('products', docs));

    await remote.upsertDocument(
      collection: 'products',
      docId: 'prod-rt-1',
      data: {
        'id': 'prod-rt-1',
        'name': 'Live Synced Item',
        'sku': 'RT-1',
        'barcode': '',
        'category': 'General',
        'costPrice': 10.0,
        'sellingPrice': 20.0,
        'lowStockThreshold': 5,
        'updatedAt': 4000,
        'isDeleted': false,
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final products = await dao.getProducts();
    expect(products.any((p) => p.id == 'prod-rt-1' && p.name == 'Live Synced Item'), isTrue);
  });
}
