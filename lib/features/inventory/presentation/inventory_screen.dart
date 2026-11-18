import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/syncable_models.dart';
import '../../../shared/widgets/app_state_widgets.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../branches/presentation/branch_controller.dart';
import 'barcode_scanner_screen.dart';
import 'inventory_controller.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && mounted) {
      _searchCtrl.text = code;
      ref.read(inventoryControllerProvider.notifier).setSearchQuery(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = ref.watch(inventoryControllerProvider);
    final branchState = ref.watch(branchControllerProvider);
    final activeBranch = branchState.activeBranch;
    final role = ref.watch(authControllerProvider).user?.role ?? UserRole.employee;

    if (inv.isLoading) {
      return const AppLoadingView(message: 'Loading inventory...');
    }
    if (inv.error != null) {
      return AppErrorView(
        message: inv.error!,
        onRetry: () => ref.read(inventoryControllerProvider.notifier).load(),
      );
    }
    if (activeBranch == null) {
      return const AppEmptyView(
        icon: Icons.store_outlined,
        title: 'No Branch Selected',
        subtitle: 'Create or select a branch to view and manage inventory.',
      );
    }

    final products = inv.filteredProducts;

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
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => ref
                      .read(inventoryControllerProvider.notifier)
                      .setSearchQuery(v),
                  decoration: InputDecoration(
                    hintText: 'Search name, SKU, barcode...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              ref
                                  .read(inventoryControllerProvider.notifier)
                                  .setSearchQuery('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.outlined(
                tooltip: 'Scan Barcode / QR',
                onPressed: _scanBarcode,
                icon: const Icon(Icons.qr_code_scanner),
              ),
              if (role.canEditProducts) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  tooltip: 'Add Product',
                  onPressed: () => _showProductDialog(context),
                  icon: const Icon(Icons.add),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              FilterChip(
                selected: inv.lowStockOnly,
                label: Text('Low Stock (${inv.lowStockCount})'),
                onSelected: (_) => ref
                    .read(inventoryControllerProvider.notifier)
                    .toggleLowStockOnly(),
              ),
              const Spacer(),
              Text(
                '${products.length} items',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: products.isEmpty
              ? AppEmptyView(
                  icon: Icons.inventory_2_outlined,
                  title: 'No products found',
                  subtitle: inv.searchQuery.isNotEmpty
                      ? 'Try a different search or clear filters.'
                      : 'Add products to start tracking stock in ${activeBranch.name}.',
                  actionLabel:
                      role.canEditProducts ? 'Add Product' : null,
                  onAction: role.canEditProducts
                      ? () => _showProductDialog(context)
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(inventoryControllerProvider.notifier).load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: products.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final p = products[index];
                      final qty = inv.stockFor(p.id);
                      final isLow = qty <= p.lowStockThreshold;
                      return _ProductCard(
                        product: p,
                        quantity: qty,
                        isLowStock: isLow,
                        onTap: () => _showProductDetailSheet(
                          context,
                          product: p,
                          branch: activeBranch,
                          quantity: qty,
                          role: role,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showProductDialog(
    BuildContext context, {
    Product? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');
    final barcodeCtrl = TextEditingController(text: existing?.barcode ?? '');
    final categoryCtrl =
        TextEditingController(text: existing?.category ?? 'General');
    final costCtrl =
        TextEditingController(text: existing?.costPrice.toString() ?? '');
    final priceCtrl =
        TextEditingController(text: existing?.sellingPrice.toString() ?? '');
    final thresholdCtrl = TextEditingController(
      text: (existing?.lowStockThreshold ?? 5).toString(),
    );
    final imageUrlCtrl = TextEditingController(text: existing?.imageUrl ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Product' : 'Edit Product'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Product Name'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: skuCtrl,
                  decoration: const InputDecoration(labelText: 'SKU'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: barcodeCtrl,
                  decoration: const InputDecoration(labelText: 'Barcode / QR'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: costCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Cost'),
                        validator: (v) => double.tryParse(v ?? '') == null
                            ? 'Invalid'
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Price'),
                        validator: (v) => double.tryParse(v ?? '') == null
                            ? 'Invalid'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: thresholdCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Low Stock Alert'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: imageUrlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await ref.read(inventoryControllerProvider.notifier).saveProduct(
            existingId: existing?.id,
            name: nameCtrl.text,
            sku: skuCtrl.text,
            barcode: barcodeCtrl.text,
            category: categoryCtrl.text,
            costPrice: double.parse(costCtrl.text),
            sellingPrice: double.parse(priceCtrl.text),
            lowStockThreshold: int.tryParse(thresholdCtrl.text) ?? 5,
            imageUrl: imageUrlCtrl.text,
          );
    }
  }

  Future<void> _showProductDetailSheet(
    BuildContext context, {
    required Product product,
    required Branch branch,
    required int quantity,
    required UserRole role,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ProductDetailSheet(
        product: product,
        branch: branch,
        initialQty: quantity,
        role: role,
        onEdit: () {
          Navigator.of(ctx).pop();
          _showProductDialog(context, existing: product);
        },
        onDelete: () async {
          final confirm = await showDialog<bool>(
            context: ctx,
            builder: (dCtx) => AlertDialog(
              title: const Text('Delete Product?'),
              content: Text(
                'Delete "${product.name}"? Deletions always win during sync.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dCtx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed: () => Navigator.of(dCtx).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            if (ctx.mounted) Navigator.of(ctx).pop();
            await ref
                .read(inventoryControllerProvider.notifier)
                .deleteProduct(product.id);
          }
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.quantity,
    required this.isLowStock,
    required this.onTap,
  });

  final Product product;
  final int quantity;
  final bool isLowStock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final syncStatus = SyncRecordStatus.values.firstWhere(
      (e) => e.name == product.syncStatus,
      orElse: () => SyncRecordStatus.synced,
    );

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                    ? Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.inventory_2_outlined,
                          size: 20,
                        ),
                      )
                    : const Icon(Icons.inventory_2_outlined, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        SyncStatusBadge(status: syncStatus),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SKU: ${product.sku} • ${product.category}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '\$${product.sellingPrice.toStringAsFixed(2)}',
                      style: AppTheme.tabularNumberStyle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isLowStock ? AppColors.errorBg : AppColors.successBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      '$quantity',
                      style: AppTheme.tabularNumberStyle.copyWith(
                        color: isLowStock ? AppColors.error : AppColors.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      isLowStock ? 'Low' : 'In Stock',
                      style: TextStyle(
                        color: isLowStock ? AppColors.error : AppColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductDetailSheet extends ConsumerStatefulWidget {
  const _ProductDetailSheet({
    required this.product,
    required this.branch,
    required this.initialQty,
    required this.role,
    required this.onEdit,
    required this.onDelete,
  });

  final Product product;
  final Branch branch;
  final int initialQty;
  final UserRole role;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  ConsumerState<_ProductDetailSheet> createState() =>
      _ProductDetailSheetState();
}

class _ProductDetailSheetState extends ConsumerState<_ProductDetailSheet> {
  final _deltaCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  List<StockMovement> _movements = [];
  bool _loadingMovements = true;

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  @override
  void dispose() {
    _deltaCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMovements() async {
    final list = await ref
        .read(inventoryControllerProvider.notifier)
        .getMovementsForProduct(widget.product.id, widget.branch.id);
    if (mounted) {
      setState(() {
        _movements = list;
        _loadingMovements = false;
      });
    }
  }

  Future<void> _applyAdjustment() async {
    final delta = int.tryParse(_deltaCtrl.text.trim());
    if (delta == null || delta == 0) return;

    await ref.read(inventoryControllerProvider.notifier).adjustStock(
          branchId: widget.branch.id,
          productId: widget.product.id,
          delta: delta,
          note: _noteCtrl.text,
        );
    _deltaCtrl.clear();
    _noteCtrl.clear();
    await _loadMovements();
  }

  @override
  Widget build(BuildContext context) {
    final inv = ref.watch(inventoryControllerProvider);
    final currentQty = inv.stockFor(widget.product.id);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ListView(
          controller: scrollController,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.product.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.role.canEditProducts)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: widget.onEdit,
                  ),
                if (widget.role.canDeleteProducts)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: widget.onDelete,
                  ),
              ],
            ),
            Text(
              '${widget.branch.name} • Current Stock: $currentQty',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (widget.role.canAdjustStock) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Adjust Stock (+/-)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _deltaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: const InputDecoration(hintText: '+10 / -2'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(hintText: 'Reason note'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _applyAdjustment,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Stock Movement History',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_loadingMovements)
              const AppLoadingView(message: 'Loading movements...')
            else if (_movements.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('No stock movements recorded yet.'),
              )
            else
              ..._movements.map((m) {
                final dt = DateFormat.MMMd().add_jm().format(
                      DateTime.fromMillisecondsSinceEpoch(m.createdAt),
                    );
                final positive = m.changeQty >= 0;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${m.reason.toUpperCase()} • $dt'),
                  subtitle: m.note.isNotEmpty ? Text(m.note) : null,
                  trailing: Text(
                    positive ? '+${m.changeQty}' : '${m.changeQty}',
                    style: AppTheme.tabularNumberStyle.copyWith(
                      color: positive ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
