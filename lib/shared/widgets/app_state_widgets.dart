import 'package:flutter/material.dart';

import 'package:nexus/core/theme/app_theme.dart';

enum SyncRecordStatus { pending, syncing, synced, failed }

/// Consistent loading placeholder.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.message = 'Loading...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Consistent empty state with optional primary action.
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent error state with retry action.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Subtle offline strip showing pending sync item count.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.isOffline,
    this.pendingCount = 0,
  });

  final bool isOffline;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    if (!isOffline) return const SizedBox.shrink();

    final text = pendingCount > 0
        ? 'Offline mode • $pendingCount pending sync'
        : 'Offline mode • Changes saved locally';

    return Material(
      color: AppColors.warningBg,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 16, color: AppColors.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill badge displaying Pending / Syncing / Synced / Failed state.
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({
    super.key,
    required this.status,
    this.onTap,
  });

  final SyncRecordStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg, icon) = switch (status) {
      SyncRecordStatus.pending => (
        'Pending',
        AppColors.warning,
        AppColors.warningBg,
        Icons.schedule,
      ),
      SyncRecordStatus.syncing => (
        'Syncing',
        AppColors.info,
        AppColors.infoBg,
        Icons.sync,
      ),
      SyncRecordStatus.synced => (
        'Synced',
        AppColors.success,
        AppColors.successBg,
        Icons.check_circle_outline,
      ),
      SyncRecordStatus.failed => (
        'Failed',
        AppColors.error,
        AppColors.errorBg,
        Icons.error_outline,
      ),
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: chip,
    );
  }
}
