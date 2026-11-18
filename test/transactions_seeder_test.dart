import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/data/local/app_database.dart';
import 'package:nexus/data/local/daos/nexus_dao.dart';
import 'package:nexus/data/models/syncable_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDb;
  late NexusDao dao;

  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => AppDatabase.createSchema(db),
      ),
    );
    appDb = AppDatabase.forTesting(db);
    dao = NexusDao(appDb);
  });

  tearDown(() async {
    await appDb.close();
  });

  test('recordTransactionAtomic updates branch stock and prevents overselling', () async {
    await dao.saveBranch(
      const Branch(
        id: 'b1',
        name: 'Main',
        location: 'HQ',
        updatedAt: 1000,
      ),
    );
    await dao.saveProduct(
      const Product(
        id: 'p1',
        name: 'Item',
        sku: 'SKU-1',
        costPrice: 10,
        sellingPrice: 25,
        updatedAt: 1000,
      ),
    );
    await dao.setBranchStock(
      branchId: 'b1',
      productId: 'p1',
      quantity: 5,
      updatedAt: 1000,
    );

    // Sale of 3 units succeeds and leaves 2 units.
    await dao.recordTransactionAtomic(
      transaction: const BusinessTransaction(
        id: 'tx-sale-1',
        branchId: 'b1',
        type: 'sale',
        totalAmount: 75,
        profitAmount: 45,
        createdBy: 'u1',
        createdAt: 2000,
        updatedAt: 2000,
        items: [
          TransactionItemModel(
            id: 'i1',
            transactionId: 'tx-sale-1',
            productId: 'p1',
            productName: 'Item',
            quantity: 3,
            unitPrice: 25,
            unitCost: 10,
          ),
        ],
      ),
      items: [(movementId: 'm1', productId: 'p1', quantity: 3)],
    );

    expect(await dao.getBranchStockQty('b1', 'p1'), 2);

    // Sale of 5 units when only 2 remain throws StateError.
    await expectLater(
      dao.recordTransactionAtomic(
        transaction: const BusinessTransaction(
          id: 'tx-sale-2',
          branchId: 'b1',
          type: 'sale',
          totalAmount: 125,
          profitAmount: 75,
          createdBy: 'u1',
          createdAt: 3000,
          updatedAt: 3000,
          items: [],
        ),
        items: [(movementId: 'm2', productId: 'p1', quantity: 5)],
      ),
      throwsStateError,
    );
  });
}
