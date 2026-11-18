import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database for offline-first persistence.
class AppDatabase {
  AppDatabase._(this._db);

  static const String dbName = 'nexus.db';
  static const int dbVersion = 1;

  final Database _db;
  Database get db => _db;

  static AppDatabase? _instance;

  /// Returns the singleton [AppDatabase], opening it if necessary.
  static Future<AppDatabase> getInstance() async {
    if (_instance != null) return _instance!;
    final dbPath = p.join(await getDatabasesPath(), dbName);
    final database = await openDatabase(
      dbPath,
      version: dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
    _instance = AppDatabase._(database);
    return _instance!;
  }

  /// Creates an [AppDatabase] backed by an existing [Database] (e.g. in-memory
  /// SQLite for unit tests).
  factory AppDatabase.forTesting(Database database) {
    return AppDatabase._(database);
  }

  /// Exposed for in-memory test database initialization.
  static Future<void> createSchema(Database db) => _onCreate(db, dbVersion);

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        uid TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        assigned_branch_id TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE branches (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        location TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        barcode TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT 'General',
        cost_price REAL NOT NULL,
        selling_price REAL NOT NULL,
        low_stock_threshold INTEGER NOT NULL DEFAULT 5,
        image_url TEXT,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE branch_stock (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        type TEXT NOT NULL,
        total_amount REAL NOT NULL,
        profit_amount REAL NOT NULL DEFAULT 0,
        notes TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transaction_items (
        id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        unit_cost REAL NOT NULL,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        change_qty INTEGER NOT NULL,
        reason TEXT NOT NULL,
        reference_id TEXT,
        note TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_transfers (
        id TEXT PRIMARY KEY,
        from_branch_id TEXT NOT NULL,
        to_branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        note TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        sync_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Indexes for fast branch-scoped queries and sync queue lookups.
    await db.execute(
      'CREATE INDEX idx_branches_sync ON branches(sync_status, updated_at)',
    );
    await db.execute(
      'CREATE INDEX idx_products_sync ON products(sync_status, updated_at)',
    );
    await db.execute(
      'CREATE INDEX idx_branch_stock_branch ON branch_stock(branch_id, product_id)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_branch ON transactions(branch_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_sync ON transactions(sync_status, updated_at)',
    );
    await db.execute(
      'CREATE INDEX idx_movements_branch ON stock_movements(branch_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_transfers_sync ON stock_transfers(sync_status, updated_at)',
    );
  }

  Future<void> close() async {
    await _db.close();
    if (identical(_instance, this)) {
      _instance = null;
    }
  }
}
