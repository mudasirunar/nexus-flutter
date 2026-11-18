import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../data/models/syncable_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../branches/presentation/branch_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';

enum TransactionFilter { all, sale, purchase, unsynced }

class TransactionsState {
  const TransactionsState({
    this.transactions = const [],
    this.filter = TransactionFilter.all,
    this.isLoading = true,
    this.error,
  });

  final List<BusinessTransaction> transactions;
  final TransactionFilter filter;
  final bool isLoading;
  final String? error;

  List<BusinessTransaction> get filtered {
    return switch (filter) {
      TransactionFilter.all => transactions,
      TransactionFilter.sale =>
        transactions.where((t) => t.type == 'sale').toList(),
      TransactionFilter.purchase =>
        transactions.where((t) => t.type == 'purchase').toList(),
      TransactionFilter.unsynced =>
        transactions.where((t) => t.syncStatus != 'synced').toList(),
    };
  }

  TransactionsState copyWith({
    List<BusinessTransaction>? transactions,
    TransactionFilter? filter,
    bool? isLoading,
    String? error,
  }) {
    return TransactionsState(
      transactions: transactions ?? this.transactions,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class CartLineInput {
  const CartLineInput({required this.product, required this.quantity});

  final Product product;
  final int quantity;
}

class TransactionsController extends Notifier<TransactionsState> {
  static const _uuid = Uuid();

  @override
  TransactionsState build() {
    final activeBranchId = ref.watch(
      branchControllerProvider.select((s) => s.activeBranch?.id),
    );
    Future.microtask(() => load(branchId: activeBranchId));
    return const TransactionsState();
  }

  Future<void> load({String? branchId}) async {
    try {
      final dao = await ref.read(nexusDaoProvider.future);
      final effectiveBranchId =
          branchId ?? ref.read(branchControllerProvider).activeBranch?.id;
      if (effectiveBranchId == null) {
        state = state.copyWith(transactions: [], isLoading: false, error: null);
        return;
      }

      final list = await dao.getTransactions(branchId: effectiveBranchId);
      state = state.copyWith(
        transactions: list,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setFilter(TransactionFilter filter) {
    state = state.copyWith(filter: filter);
  }

  Future<BusinessTransaction> createTransaction({
    required String branchId,
    required String type, // 'sale' | 'purchase'
    required List<CartLineInput> lines,
    String notes = '',
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Add at least one product.');
    }

    final dao = await ref.read(nexusDaoProvider.future);
    final userId = ref.read(authControllerProvider).user?.uid ?? 'unknown';
    final now = DateTime.now().millisecondsSinceEpoch;
    final txId = _uuid.v4();

    double total = 0;
    double profit = 0;
    final txItems = <TransactionItemModel>[];
    final movementInputs =
        <({String movementId, String productId, int quantity})>[];

    for (final line in lines) {
      final unitPrice = type == 'sale'
          ? line.product.sellingPrice
          : line.product.costPrice;
      total += unitPrice * line.quantity;
      if (type == 'sale') {
        profit += (line.product.sellingPrice - line.product.costPrice) *
            line.quantity;
      }

      txItems.add(
        TransactionItemModel(
          id: _uuid.v4(),
          transactionId: txId,
          productId: line.product.id,
          productName: line.product.name,
          quantity: line.quantity,
          unitPrice: unitPrice,
          unitCost: line.product.costPrice,
        ),
      );
      movementInputs.add((
        movementId: _uuid.v4(),
        productId: line.product.id,
        quantity: line.quantity,
      ));
    }

    final tx = BusinessTransaction(
      id: txId,
      branchId: branchId,
      type: type,
      totalAmount: total,
      profitAmount: profit,
      notes: notes.trim(),
      createdBy: userId,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
      items: txItems,
    );

    final updatedStocks = await dao.recordTransactionAtomic(
      transaction: tx,
      items: movementInputs,
    );

    // Trigger local low-stock alerts if any sold item hit threshold.
    for (final stock in updatedStocks) {
      final product = lines
          .firstWhere((l) => l.product.id == stock.productId)
          .product;
      if (stock.newQty <= product.lowStockThreshold) {
        await NotificationService.instance.showLocalNotification(
          title: 'Low Stock Alert: ${product.name}',
          body: 'Remaining stock is ${stock.newQty} units.',
          payload: 'inventory',
        );
      }
    }

    await load(branchId: branchId);
    await ref.read(inventoryControllerProvider.notifier).load(branchId: branchId);
    await ref.read(branchControllerProvider.notifier).load();
    await ref.read(syncControllerProvider.notifier).refreshQueueCounts();

    final online = ref.read(isOnlineProvider).value ?? false;
    if (online) {
      await ref.read(syncControllerProvider.notifier).syncNow();
      await load(branchId: branchId);
    }

    return tx;
  }

  Future<void> retryTransaction(String txId) async {
    final dao = await ref.read(nexusDaoProvider.future);
    await dao.updateSyncStatus(
      table: 'transactions',
      id: txId,
      status: 'pending',
    );
    await ref.read(syncControllerProvider.notifier).syncNow();
    await load();
  }
}

final transactionsControllerProvider =
    NotifierProvider<TransactionsController, TransactionsState>(
  TransactionsController.new,
);
