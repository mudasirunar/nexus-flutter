import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../data/models/syncable_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../branches/presentation/branch_controller.dart';

class InventoryState {
  const InventoryState({
    this.products = const [],
    this.stockByProduct = const {},
    this.searchQuery = '',
    this.lowStockOnly = false,
    this.isLoading = true,
    this.error,
  });

  final List<Product> products;
  final Map<String, int> stockByProduct;
  final String searchQuery;
  final bool lowStockOnly;
  final bool isLoading;
  final String? error;

  int stockFor(String productId) => stockByProduct[productId] ?? 0;

  List<Product> get filteredProducts {
    final q = searchQuery.trim().toLowerCase();
    return products.where((p) {
      if (lowStockOnly && stockFor(p.id) > p.lowStockThreshold) {
        return false;
      }
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
    }).toList();
  }

  int get lowStockCount =>
      products.where((p) => stockFor(p.id) <= p.lowStockThreshold).length;

  InventoryState copyWith({
    List<Product>? products,
    Map<String, int>? stockByProduct,
    String? searchQuery,
    bool? lowStockOnly,
    bool? isLoading,
    String? error,
  }) {
    return InventoryState(
      products: products ?? this.products,
      stockByProduct: stockByProduct ?? this.stockByProduct,
      searchQuery: searchQuery ?? this.searchQuery,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class InventoryController extends Notifier<InventoryState> {
  static const _uuid = Uuid();

  @override
  InventoryState build() {
    final activeBranchId = ref.watch(
      branchControllerProvider.select((s) => s.activeBranch?.id),
    );
    Future.microtask(() => load(branchId: activeBranchId));
    return const InventoryState();
  }

  Future<void> load({String? branchId}) async {
    try {
      final dao = await ref.read(nexusDaoProvider.future);
      final products = await dao.getProducts();
      final effectiveBranchId =
          branchId ?? ref.read(branchControllerProvider).activeBranch?.id;
      final stockMap = effectiveBranchId != null
          ? await dao.getBranchStockMap(effectiveBranchId)
          : <String, int>{};

      state = state.copyWith(
        products: products,
        stockByProduct: stockMap,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void toggleLowStockOnly() {
    state = state.copyWith(lowStockOnly: !state.lowStockOnly);
  }

  Future<void> saveProduct({
    String? existingId,
    required String name,
    required String sku,
    String barcode = '',
    String category = 'General',
    required double costPrice,
    required double sellingPrice,
    int lowStockThreshold = 5,
    String? imageUrl,
  }) async {
    final dao = await ref.read(nexusDaoProvider.future);
    final now = DateTime.now().millisecondsSinceEpoch;

    await dao.saveProduct(
      Product(
        id: existingId ?? _uuid.v4(),
        name: name.trim(),
        sku: sku.trim(),
        barcode: barcode.trim(),
        category: category.trim().isEmpty ? 'General' : category.trim(),
        costPrice: costPrice,
        sellingPrice: sellingPrice,
        lowStockThreshold: lowStockThreshold,
        imageUrl: imageUrl?.trim().isEmpty == true ? null : imageUrl?.trim(),
        updatedAt: now,
        syncStatus: 'pending',
      ),
    );

    await load();
    _triggerBackgroundSync();
  }

  Future<void> deleteProduct(String productId) async {
    final dao = await ref.read(nexusDaoProvider.future);
    final now = DateTime.now().millisecondsSinceEpoch;
    await dao.softDeleteRecord(table: 'products', id: productId, deletedAt: now);
    await load();
    _triggerBackgroundSync();
  }

  Future<void> adjustStock({
    required String branchId,
    required String productId,
    required int delta,
    String note = '',
  }) async {
    if (delta == 0) return;
    final dao = await ref.read(nexusDaoProvider.future);
    final userId = ref.read(authControllerProvider).user?.uid ?? 'unknown';
    final now = DateTime.now().millisecondsSinceEpoch;

    await dao.adjustBranchStock(
      movementId: _uuid.v4(),
      branchId: branchId,
      productId: productId,
      delta: delta,
      reason: 'adjustment',
      createdBy: userId,
      note: note.trim(),
      timestampMs: now,
    );

    await load(branchId: branchId);
    await ref.read(branchControllerProvider.notifier).load();
    _triggerBackgroundSync();
  }

  Future<List<StockMovement>> getMovementsForProduct(
    String productId,
    String branchId,
  ) async {
    final dao = await ref.read(nexusDaoProvider.future);
    return dao.getStockMovements(branchId: branchId, productId: productId);
  }

  void _triggerBackgroundSync() {
    ref.read(syncControllerProvider.notifier).refreshQueueCounts();
    final online = ref.read(isOnlineProvider).value ?? false;
    if (online) {
      ref.read(syncControllerProvider.notifier).syncNow();
    }
  }
}

final inventoryControllerProvider =
    NotifierProvider<InventoryController, InventoryState>(
  InventoryController.new,
);
