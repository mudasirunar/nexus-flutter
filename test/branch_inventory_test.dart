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

  test('Branch-scoped stock stays isolated and transfers update both branches', () async {
    await dao.saveBranch(
      const Branch(
        id: 'b1',
        name: 'Downtown',
        location: 'Main St',
        updatedAt: 1000,
      ),
    );
    await dao.saveBranch(
      const Branch(
        id: 'b2',
        name: 'Airport',
        location: 'Terminal 2',
        updatedAt: 1000,
      ),
    );
    await dao.saveProduct(
      const Product(
        id: 'p1',
        name: 'USB-C Hub',
        sku: 'HUB-01',
        costPrice: 20,
        sellingPrice: 40,
        updatedAt: 1000,
      ),
    );

    await dao.setBranchStock(
      branchId: 'b1',
      productId: 'p1',
      quantity: 30,
      updatedAt: 1000,
    );
    await dao.setBranchStock(
      branchId: 'b2',
      productId: 'p1',
      quantity: 5,
      updatedAt: 1000,
    );

    // Verify isolation between branches.
    expect((await dao.getBranchStockMap('b1'))['p1'], 30);
    expect((await dao.getBranchStockMap('b2'))['p1'], 5);

    // Execute inter-branch transfer of 12 units from b1 -> b2.
    await dao.executeStockTransfer(
      transfer: const StockTransfer(
        id: 'tr-1',
        fromBranchId: 'b1',
        toBranchId: 'b2',
        productId: 'p1',
        quantity: 12,
        createdBy: 'u1',
        createdAt: 2000,
        updatedAt: 2000,
      ),
      outMovementId: 'mov-out',
      inMovementId: 'mov-in',
    );

    expect((await dao.getBranchStockMap('b1'))['p1'], 18);
    expect((await dao.getBranchStockMap('b2'))['p1'], 17);

    final movements = await dao.getStockMovements(productId: 'p1');
    expect(movements.length, 2);
  });
}
