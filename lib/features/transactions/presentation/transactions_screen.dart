import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/syncable_models.dart';
import '../../../shared/widgets/app_state_widgets.dart';
import '../../branches/presentation/branch_controller.dart';
import '../../inventory/presentation/barcode_scanner_screen.dart';
import '../../inventory/presentation/inventory_controller.dart';
import 'transactions_controller.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txState = ref.watch(transactionsControllerProvider);
    final branch = ref.watch(branchControllerProvider).activeBranch;

    if (txState.isLoading) {
      return const AppLoadingView(message: 'Loading transactions...');
    }
    if (txState.error != null) {
      return AppErrorView(
        message: txState.error!,
        onRetry: () => ref.read(transactionsControllerProvider.notifier).load(),
      );
    }
    if (branch == null) {
      return const AppEmptyView(
        icon: Icons.store_outlined,
        title: 'No Branch Selected',
        subtitle: 'Create or select a branch to record sales and purchases.',
      );
    }

    final list = txState.filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openCreateSheet(context, ref, branch, 'sale'),
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('New Sale'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _openCreateSheet(context, ref, branch, 'purchase'),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('New Purchase'),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: TransactionFilter.values.map((f) {
              final label = switch (f) {
                TransactionFilter.all => 'All',
                TransactionFilter.sale => 'Sales',
                TransactionFilter.purchase => 'Purchases',
                TransactionFilter.unsynced => 'Pending / Failed',
              };
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  label: Text(label),
                  selected: txState.filter == f,
                  onSelected: (_) => ref
                      .read(transactionsControllerProvider.notifier)
                      .setFilter(f),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: list.isEmpty
              ? AppEmptyView(
                  icon: Icons.receipt_long_outlined,
                  title: 'No Transactions Yet',
                  subtitle:
                      'Create an offline or online sale/purchase for ${branch.name}.',
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(transactionsControllerProvider.notifier).load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final tx = list[index];
                      return _TransactionCard(
                        tx: tx,
                        onRetry: () => ref
                            .read(transactionsControllerProvider.notifier)
                            .retryTransaction(tx.id),
                        onTap: () => _showTxDetail(context, tx),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _openCreateSheet(
    BuildContext context,
    WidgetRef ref,
    Branch branch,
    String type,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewTransactionSheet(branch: branch, type: type),
    );
  }

  void _showTxDetail(BuildContext context, BusinessTransaction tx) {
    final dt = DateFormat.yMMMd().add_jm().format(
          DateTime.fromMillisecondsSinceEpoch(tx.createdAt),
        );
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tx.type == 'sale' ? 'Sale' : 'Purchase'} • \$${tx.totalAmount.toStringAsFixed(2)}',
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(dt, style: Theme.of(ctx).textTheme.bodySmall),
            if (tx.notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(tx.notes),
            ],
            if (tx.syncError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Sync Error: ${tx.syncError}',
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
            const Divider(height: AppSpacing.xl),
            ...tx.items.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.productName),
                subtitle: Text(
                  '${item.quantity} × \$${item.unitPrice.toStringAsFixed(2)}',
                ),
                trailing: Text(
                  '\$${(item.quantity * item.unitPrice).toStringAsFixed(2)}',
                  style: AppTheme.tabularNumberStyle.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.tx,
    required this.onRetry,
    required this.onTap,
  });

  final BusinessTransaction tx;
  final VoidCallback onRetry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSale = tx.type == 'sale';
    final dt = DateFormat.MMMd().add_jm().format(
          DateTime.fromMillisecondsSinceEpoch(tx.createdAt),
        );
    final syncStatus = SyncRecordStatus.values.firstWhere(
      (e) => e.name == tx.syncStatus,
      orElse: () => SyncRecordStatus.synced,
    );

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: isSale ? AppColors.successBg : AppColors.infoBg,
          child: Icon(
            isSale ? Icons.arrow_upward : Icons.arrow_downward,
            color: isSale ? AppColors.success : AppColors.info,
            size: 18,
          ),
        ),
        title: Text(
          '${isSale ? 'Sale' : 'Purchase'} • \$${tx.totalAmount.toStringAsFixed(2)}',
          style: AppTheme.tabularNumberStyle.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text('${tx.items.length} items • $dt'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SyncStatusBadge(
              status: syncStatus,
              onTap: syncStatus == SyncRecordStatus.failed ? onRetry : null,
            ),
            if (syncStatus == SyncRecordStatus.failed)
              IconButton(
                tooltip: 'Retry Sync',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: onRetry,
              ),
          ],
        ),
      ),
    );
  }
}

class _NewTransactionSheet extends ConsumerStatefulWidget {
  const _NewTransactionSheet({required this.branch, required this.type});

  final Branch branch;
  final String type;

  @override
  ConsumerState<_NewTransactionSheet> createState() =>
      _NewTransactionSheetState();
}

class _NewTransactionSheetState extends ConsumerState<_NewTransactionSheet> {
  final Map<String, int> _cart = {};
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanAndAdd(List<Product> products) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || !mounted) return;
    final match = products.where(
      (p) => p.barcode == code || p.sku == code,
    );
    if (match.isEmpty) {
      setState(() => _error = 'No product matches barcode "$code".');
      return;
    }
    final p = match.first;
    setState(() {
      _error = null;
      _cart[p.id] = (_cart[p.id] ?? 0) + 1;
    });
  }

  Future<void> _submit(List<Product> products) async {
    if (_cart.isEmpty) {
      setState(() => _error = 'Add at least one item.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final lines = _cart.entries.map((e) {
        final product = products.firstWhere((p) => p.id == e.key);
        return CartLineInput(product: product, quantity: e.value);
      }).toList();

      await ref.read(transactionsControllerProvider.notifier).createTransaction(
            branchId: widget.branch.id,
            type: widget.type,
            lines: lines,
            notes: _notesCtrl.text,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = ref.watch(inventoryControllerProvider);
    final products = inv.products;
    final isSale = widget.type == 'sale';

    double total = 0;
    for (final entry in _cart.entries) {
      final p = products.where((x) => x.id == entry.key).firstOrNull;
      if (p != null) {
        total += (isSale ? p.sellingPrice : p.costPrice) * entry.value;
      }
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'New ${isSale ? 'Sale' : 'Purchase'} • ${widget.branch.name}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Scan Barcode',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () => _scanAndAdd(products),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: products.isEmpty
                  ? const AppEmptyView(
                      icon: Icons.inventory_2_outlined,
                      title: 'No Products Available',
                      subtitle: 'Add products in Inventory first.',
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final p = products[index];
                        final qty = _cart[p.id] ?? 0;
                        final stock = inv.stockFor(p.id);
                        final price = isSale ? p.sellingPrice : p.costPrice;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.name),
                          subtitle: Text(
                            '\$${price.toStringAsFixed(2)} • Stock: $stock',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: qty <= 0
                                    ? null
                                    : () => setState(() {
                                          if (qty == 1) {
                                            _cart.remove(p.id);
                                          } else {
                                            _cart[p.id] = qty - 1;
                                          }
                                        }),
                              ),
                              Text(
                                '$qty',
                                style: AppTheme.tabularNumberStyle.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: (isSale && qty >= stock)
                                    ? null
                                    : () => setState(() => _cart[p.id] = qty + 1),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(hintText: 'Notes (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _submitting ? null : () => _submit(products),
              child: Text(
                _submitting
                    ? 'Saving...'
                    : 'Complete ${isSale ? 'Sale' : 'Purchase'} (\$${total.toStringAsFixed(2)})',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
