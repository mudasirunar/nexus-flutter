import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_state_widgets.dart';
import 'transactions_controller.dart';

class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncControllerProvider);
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final txState = ref.watch(transactionsControllerProvider);
    final unsyncedTxs =
        txState.transactions.where((t) => t.syncStatus != 'synced').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Sync Center')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isOnline ? Icons.cloud_done_outlined : Icons.cloud_off,
                        color: isOnline ? AppColors.success : AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: syncState.isSyncing
                            ? null
                            : () => ref
                                .read(syncControllerProvider.notifier)
                                .syncNow(),
                        icon: const Icon(Icons.sync, size: 18),
                        label: Text(
                          syncState.isSyncing ? 'Syncing...' : 'Sync Now',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Pending: ${syncState.pendingCount} • Failed: ${syncState.failedCount}',
                  ),
                  if (syncState.lastSyncedAt != null)
                    Text(
                      'Last synced: ${DateFormat.jm().format(syncState.lastSyncedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (syncState.lastError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Last error: ${syncState.lastError}',
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Unsynced Transactions (${unsyncedTxs.length})',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (unsyncedTxs.isEmpty)
            const AppEmptyView(
              icon: Icons.check_circle_outline,
              title: 'All Caught Up',
              subtitle: 'Every local transaction is synced with Firestore.',
            )
          else
            ...unsyncedTxs.map((tx) {
              final status = SyncRecordStatus.values.firstWhere(
                (e) => e.name == tx.syncStatus,
                orElse: () => SyncRecordStatus.pending,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Card(
                  child: ListTile(
                    title: Text(
                      '${tx.type.toUpperCase()} • \$${tx.totalAmount.toStringAsFixed(2)}',
                    ),
                    subtitle: Text(tx.syncError ?? 'Queued for synchronization'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SyncStatusBadge(status: status),
                        IconButton(
                          tooltip: 'Retry',
                          icon: const Icon(Icons.refresh),
                          onPressed: () => ref
                              .read(transactionsControllerProvider.notifier)
                              .retryTransaction(tx.id),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
