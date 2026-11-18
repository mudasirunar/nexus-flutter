import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/connectivity_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../features/analytics/presentation/analytics_controller.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/branches/presentation/branch_controller.dart';
import '../../features/branches/presentation/branches_screen.dart';
import '../../features/inventory/presentation/inventory_controller.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/transactions/presentation/sync_center_screen.dart';
import '../../features/transactions/presentation/transactions_controller.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import 'app_state_widgets.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.initialize(
      onNotificationTap: _handleNotificationRoute,
    );
    Future.microtask(_initialSyncAndStartRealtime);
  }

  Future<void> _initialSyncAndStartRealtime() async {
    await ref.read(syncControllerProvider.notifier).syncNow();
    if (!mounted) return;
    await _reloadFeatureControllers();
    await ref.read(syncControllerProvider.notifier).startRealtimeListeners();
  }

  Future<void> _reloadFeatureControllers() async {
    if (!mounted) return;
    await ref.read(branchControllerProvider.notifier).load();
    await ref.read(inventoryControllerProvider.notifier).load();
    await ref.read(transactionsControllerProvider.notifier).load();
    await ref.read(analyticsControllerProvider.notifier).load();
  }

  void _handleNotificationRoute(String? route) {
    if (!mounted || route == null) return;
    switch (route) {
      case 'inventory':
        setState(() => _selectedIndex = 1);
      case 'sales':
        setState(() => _selectedIndex = 2);
      case 'branches':
        setState(() => _selectedIndex = 3);
      case 'sync':
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SyncCenterScreen()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Automatically reload UI whenever real-time Firestore snapshots update SQLite.
    ref.listen<int>(
      syncControllerProvider.select((s) => s.dataVersion),
      (_, _) => _reloadFeatureControllers(),
    );

    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final syncState = ref.watch(syncControllerProvider);
    final branchState = ref.watch(branchControllerProvider);
    final activeBranch = branchState.activeBranch;
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    final destinations = const [
      NavigationDestination(
        icon: Icon(Icons.analytics_outlined),
        selectedIcon: Icon(Icons.analytics),
        label: 'Dashboard',
      ),
      NavigationDestination(
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
        label: 'Inventory',
      ),
      NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: 'Sales',
      ),
      NavigationDestination(
        icon: Icon(Icons.store_outlined),
        selectedIcon: Icon(Icons.store),
        label: 'Branches',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ];

    final pages = [
      const AnalyticsScreen(),
      const InventoryScreen(),
      const TransactionsScreen(),
      const BranchesScreen(),
      const _SettingsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: branchState.branches.isEmpty
            ? const Text('NEXUS')
            : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: activeBranch?.id,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onChanged: (id) {
                    if (id != null) {
                      ref
                          .read(branchControllerProvider.notifier)
                          .selectBranch(id);
                    }
                  },
                  items: branchState.branches
                      .map(
                        (b) => DropdownMenuItem(
                          value: b.id,
                          child: Text(
                            b.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
        actions: [
          IconButton(
            tooltip: syncState.isSyncing ? 'Syncing...' : 'Sync Now',
            onPressed: syncState.isSyncing
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
            icon: Badge(
              isLabelVisible:
                  syncState.pendingCount + syncState.failedCount > 0,
              label: Text('${syncState.pendingCount + syncState.failedCount}'),
              child: syncState.isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(
            isOffline: !isOnline,
            pendingCount: syncState.pendingCount + syncState.failedCount,
          ),
          Expanded(
            child: Row(
              children: [
                if (isWide)
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (i) =>
                        setState(() => _selectedIndex = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: destinations
                        .map(
                          (d) => NavigationRailDestination(
                            icon: d.icon,
                            selectedIcon: d.selectedIcon,
                            label: Text(d.label),
                          ),
                        )
                        .toList(),
                  ),
                Expanded(child: pages[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              destinations: destinations,
            ),
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final syncState = ref.watch(syncControllerProvider);
    final user = auth.user;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user?.name ?? 'User'),
            subtitle: Text(
              '${user?.email ?? ''} • Role: ${user?.role.value.toUpperCase() ?? ''}',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (sel) => ref
                      .read(themeControllerProvider.notifier)
                      .setThemeMode(sel.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Biometric Unlock'),
                subtitle: const Text('Require fingerprint / Face ID on launch'),
                value: auth.biometricEnabled,
                onChanged: (v) => ref
                    .read(authControllerProvider.notifier)
                    .setBiometricEnabled(v),
              ),
              const Divider(),
              ListTile(
                title: const Text('Sync Center'),
                subtitle: Text(
                  'Pending: ${syncState.pendingCount} • Failed: ${syncState.failedCount}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SyncCenterScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton.icon(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout, color: AppColors.error),
          label: const Text(
            'Sign Out',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      ],
    );
  }
}
