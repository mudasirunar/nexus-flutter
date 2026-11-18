import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/syncable_models.dart';
import '../../../shared/widgets/app_state_widgets.dart';
import '../../../shared/widgets/skeleton_widgets.dart';
import '../../auth/presentation/auth_controller.dart';
import 'analytics_controller.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(analyticsControllerProvider);
    final role = ref.watch(authControllerProvider).user?.role ?? UserRole.employee;

    if (data.isLoading) {
      return const DashboardSkeleton();
    }
    if (data.error != null) {
      return AppErrorView(
        message: data.error!,
        onRetry: () => ref.read(analyticsControllerProvider.notifier).load(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(analyticsControllerProvider.notifier).load(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('All Branches')),
                  ButtonSegment(value: false, label: Text('Active Branch')),
                ],
                selected: {data.allBranches},
                onSelectionChanged: (sel) => ref
                    .read(analyticsControllerProvider.notifier)
                    .toggleScope(sel.first),
              ),
              DropdownButton<AnalyticsRange>(
                value: data.range,
                onChanged: (r) {
                  if (r != null) {
                    ref.read(analyticsControllerProvider.notifier).setRange(r);
                  }
                },
                items: const [
                  DropdownMenuItem(
                    value: AnalyticsRange.week7,
                    child: Text('Last 7 Days'),
                  ),
                  DropdownMenuItem(
                    value: AnalyticsRange.days30,
                    child: Text('Last 30 Days'),
                  ),
                  DropdownMenuItem(
                    value: AnalyticsRange.days90,
                    child: Text('Last 90 Days'),
                  ),
                  DropdownMenuItem(
                    value: AnalyticsRange.all,
                    child: Text('All Time'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 680 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                childAspectRatio: 1.55,
                children: [
                  _KpiCard(
                    label: 'Total Sales',
                    value: '\$${data.totalSales.toStringAsFixed(0)}',
                    color: AppColors.success,
                  ),
                  _KpiCard(
                    label: 'Purchases',
                    value: '\$${data.totalPurchases.toStringAsFixed(0)}',
                    color: AppColors.info,
                  ),
                  _KpiCard(
                    label: 'Net Profit',
                    value: role.canViewProfitAnalytics
                        ? '\$${data.netProfit.toStringAsFixed(0)}'
                        : 'Restricted',
                    color: AppColors.warning,
                  ),
                  _KpiCard(
                    label: 'Inventory Value',
                    value: '\$${data.inventoryValue.toStringAsFixed(0)}',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _TrendChartCard(buckets: data.trendBuckets),
          const SizedBox(height: AppSpacing.lg),
          _BranchComparisonCard(stats: data.branchComparison),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Best-Selling Products',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (data.topProducts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Text('No sales recorded in this period.'),
                    )
                  else
                    ...data.topProducts.map(
                      (p) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.name),
                        subtitle: Text('${p.unitsSold} units sold'),
                        trailing: Text(
                          '\$${p.revenue.toStringAsFixed(2)}',
                          style: AppTheme.tabularNumberStyle.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              value,
              style: AppTheme.tabularNumberStyle.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({required this.buckets});

  final List<TimeBucketStat> buckets;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales & Purchases Trend',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (buckets.isEmpty)
              const SizedBox(
                height: 140,
                child: Center(child: Text('No chart data for selected range.')),
              )
            else
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    gridData: const FlGridData(show: true),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, _) {
                            final idx = val.toInt();
                            if (idx < 0 || idx >= buckets.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                buckets[idx].label,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(buckets.length, (i) {
                      final b = buckets[i];
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: b.sales,
                            color: AppColors.success,
                            width: 10,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          BarChartRodData(
                            toY: b.purchases,
                            color: AppColors.info,
                            width: 10,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchComparisonCard extends StatelessWidget {
  const _BranchComparisonCard({required this.stats});

  final List<BranchSalesStat> stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Branch Sales Comparison',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (stats.isEmpty)
              const SizedBox(
                height: 120,
                child: Center(child: Text('No branch sales data yet.')),
              )
            else
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    gridData: const FlGridData(show: true),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, _) {
                            final idx = val.toInt();
                            if (idx < 0 || idx >= stats.length) {
                              return const SizedBox.shrink();
                            }
                            final name = stats[idx].branchName;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                name.length > 8
                                    ? '${name.substring(0, 8)}…'
                                    : name,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(stats.length, (i) {
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: stats[i].totalSales,
                            color: Theme.of(context).colorScheme.primary,
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
