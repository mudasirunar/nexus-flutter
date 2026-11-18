import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/syncable_models.dart';
import '../../../shared/widgets/app_state_widgets.dart';
import '../../../shared/widgets/skeleton_widgets.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import 'branch_controller.dart';

class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(branchControllerProvider);
    final inv = ref.watch(inventoryControllerProvider);
    final role = ref.watch(authControllerProvider).user?.role ?? UserRole.employee;

    if (state.isLoading) {
      return const ListSkeleton();
    }
    if (state.error != null) {
      return AppErrorView(
        message: state.error!,
        onRetry: () => ref.read(branchControllerProvider.notifier).load(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: TabBar(
                    tabs: [
                      Tab(text: 'Branches'),
                      Tab(text: 'Stock Transfers'),
                    ],
                  ),
                ),
                if (role.canManageBranches)
                  IconButton.filled(
                    tooltip: 'Add Branch',
                    onPressed: () => _showBranchDialog(context, ref),
                    icon: const Icon(Icons.add_business_outlined),
                  ),
                if (role.canTransferStock && state.branches.length >= 2) ...[
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.outlined(
                    tooltip: 'Transfer Stock',
                    onPressed: () => _showTransferDialog(
                      context,
                      ref,
                      state.branches,
                      inv.products,
                    ),
                    icon: const Icon(Icons.swap_horiz),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _BranchesList(state: state, role: role),
                _TransfersHistory(
                  transfers: state.transfers,
                  branches: state.branches,
                  products: inv.products,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showBranchDialog(
    BuildContext context,
    WidgetRef ref, {
    Branch? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final locCtrl = TextEditingController(text: existing?.location ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New Branch' : 'Edit Branch'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Branch Name'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: locCtrl,
                decoration: const InputDecoration(labelText: 'Location'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
            ],
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

    if (ok == true) {
      await ref.read(branchControllerProvider.notifier).saveBranch(
            existingId: existing?.id,
            name: nameCtrl.text,
            location: locCtrl.text,
            phone: phoneCtrl.text,
          );
    }
  }

  static Future<void> _showTransferDialog(
    BuildContext context,
    WidgetRef ref,
    List<Branch> branches,
    List<Product> products,
  ) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add products before transferring stock.')),
      );
      return;
    }

    String fromId = branches.first.id;
    String toId = branches[1].id;
    String productId = products.first.id;
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Transfer Stock'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: fromId,
                  decoration: const InputDecoration(labelText: 'From Branch'),
                  items: branches
                      .map(
                        (b) => DropdownMenuItem(value: b.id, child: Text(b.name)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => fromId = v);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: toId,
                  decoration: const InputDecoration(labelText: 'To Branch'),
                  items: branches
                      .map(
                        (b) => DropdownMenuItem(value: b.id, child: Text(b.name)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => toId = v);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: productId,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: products
                      .map(
                        (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => productId = v);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
        await ref.read(branchControllerProvider.notifier).transferStock(
              fromBranchId: fromId,
              toBranchId: toId,
              productId: productId,
              quantity: qty,
              note: noteCtrl.text,
            );
        await ref.read(inventoryControllerProvider.notifier).load();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }
}

class _BranchesList extends ConsumerWidget {
  const _BranchesList({required this.state, required this.role});

  final BranchState state;
  final UserRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.branches.isEmpty) {
      return AppEmptyView(
        icon: Icons.store_mall_directory_outlined,
        title: 'No Branches Yet',
        subtitle: 'Create your first branch to organize inventory and sales.',
        actionLabel: role.canManageBranches ? 'Create Branch' : null,
        onAction: role.canManageBranches
            ? () => BranchesScreen._showBranchDialog(context, ref)
            : null,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: state.branches.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final b = state.branches[index];
        final isActive = b.id == state.activeBranch?.id;
        final summary = state.summaries[b.id];

        return Card(
          child: ListTile(
            onTap: () =>
                ref.read(branchControllerProvider.notifier).selectBranch(b.id),
            leading: Icon(
              isActive ? Icons.check_circle : Icons.store_outlined,
              color: isActive ? AppColors.success : null,
            ),
            title: Text(
              b.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${b.location} • ${summary?.stockUnits ?? 0} units • \$${(summary?.salesTotal ?? 0).toStringAsFixed(2)} sales',
            ),
            trailing: role.canManageBranches
                ? PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') {
                        BranchesScreen._showBranchDialog(
                          context,
                          ref,
                          existing: b,
                        );
                      } else if (action == 'delete') {
                        await ref
                            .read(branchControllerProvider.notifier)
                            .deleteBranch(b.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _TransfersHistory extends StatelessWidget {
  const _TransfersHistory({
    required this.transfers,
    required this.branches,
    required this.products,
  });

  final List<StockTransfer> transfers;
  final List<Branch> branches;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) {
      return const AppEmptyView(
        icon: Icons.swap_horiz,
        title: 'No Stock Transfers',
        subtitle: 'Inter-branch stock transfers will appear here.',
      );
    }

    final branchNames = {for (final b in branches) b.id: b.name};
    final productNames = {for (final p in products) p.id: p.name};

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: transfers.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final t = transfers[index];
        final dt = DateFormat.MMMd().add_jm().format(
              DateTime.fromMillisecondsSinceEpoch(t.createdAt),
            );
        final status = SyncRecordStatus.values.firstWhere(
          (e) => e.name == t.syncStatus,
          orElse: () => SyncRecordStatus.synced,
        );

        return Card(
          child: ListTile(
            title: Text(
              '${productNames[t.productId] ?? t.productId} (${t.quantity} units)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${branchNames[t.fromBranchId] ?? t.fromBranchId} → ${branchNames[t.toBranchId] ?? t.toBranchId}\n$dt',
            ),
            isThreeLine: true,
            trailing: SyncStatusBadge(status: status),
          ),
        );
      },
    );
  }
}
