import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../branches/presentation/branch_controller.dart';

enum AnalyticsRange { week7, days30, days90, all }

class TopProductStat {
  const TopProductStat({
    required this.productId,
    required this.name,
    required this.unitsSold,
    required this.revenue,
  });

  final String productId;
  final String name;
  final int unitsSold;
  final double revenue;
}

class BranchSalesStat {
  const BranchSalesStat({required this.branchName, required this.totalSales});

  final String branchName;
  final double totalSales;
}

class TimeBucketStat {
  const TimeBucketStat({
    required this.label,
    required this.sales,
    required this.purchases,
  });

  final String label;
  final double sales;
  final double purchases;
}

class AnalyticsData {
  const AnalyticsData({
    this.totalSales = 0,
    this.totalPurchases = 0,
    this.netProfit = 0,
    this.inventoryValue = 0,
    this.topProducts = const [],
    this.branchComparison = const [],
    this.trendBuckets = const [],
    this.range = AnalyticsRange.days30,
    this.allBranches = true,
    this.isLoading = true,
    this.error,
  });

  final double totalSales;
  final double totalPurchases;
  final double netProfit;
  final double inventoryValue;
  final List<TopProductStat> topProducts;
  final List<BranchSalesStat> branchComparison;
  final List<TimeBucketStat> trendBuckets;
  final AnalyticsRange range;
  final bool allBranches;
  final bool isLoading;
  final String? error;

  AnalyticsData copyWith({
    double? totalSales,
    double? totalPurchases,
    double? netProfit,
    double? inventoryValue,
    List<TopProductStat>? topProducts,
    List<BranchSalesStat>? branchComparison,
    List<TimeBucketStat>? trendBuckets,
    AnalyticsRange? range,
    bool? allBranches,
    bool? isLoading,
    String? error,
  }) {
    return AnalyticsData(
      totalSales: totalSales ?? this.totalSales,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      netProfit: netProfit ?? this.netProfit,
      inventoryValue: inventoryValue ?? this.inventoryValue,
      topProducts: topProducts ?? this.topProducts,
      branchComparison: branchComparison ?? this.branchComparison,
      trendBuckets: trendBuckets ?? this.trendBuckets,
      range: range ?? this.range,
      allBranches: allBranches ?? this.allBranches,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AnalyticsController extends Notifier<AnalyticsData> {
  @override
  AnalyticsData build() {
    ref.watch(branchControllerProvider.select((s) => s.activeBranch?.id));
    Future.microtask(load);
    return const AnalyticsData();
  }

  void setRange(AnalyticsRange range) {
    state = state.copyWith(range: range);
    load();
  }

  void toggleScope(bool allBranches) {
    state = state.copyWith(allBranches: allBranches);
    load();
  }

  Future<void> load() async {
    try {
      final dao = await ref.read(nexusDaoProvider.future);
      final branchState = ref.read(branchControllerProvider);
      final activeBranchId = branchState.activeBranch?.id;
      final branches = await dao.getBranches();
      final products = await dao.getProducts();
      final allTxs = await dao.getTransactions();

      final now = DateTime.now();
      final cutoffMs = switch (state.range) {
        AnalyticsRange.week7 =>
          now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
        AnalyticsRange.days30 =>
          now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
        AnalyticsRange.days90 =>
          now.subtract(const Duration(days: 90)).millisecondsSinceEpoch,
        AnalyticsRange.all => 0,
      };

      final scopedTxs = allTxs.where((t) {
        if (t.createdAt < cutoffMs) return false;
        if (!state.allBranches && activeBranchId != null) {
          return t.branchId == activeBranchId;
        }
        return true;
      }).toList();

      double sales = 0;
      double purchases = 0;
      double profit = 0;
      final productMap = <String, ({String name, int qty, double rev})>{};
      final branchSalesMap = <String, double>{};
      final bucketSales = <String, double>{};
      final bucketPurchases = <String, double>{};

      for (final tx in scopedTxs) {
        final dt = DateTime.fromMillisecondsSinceEpoch(tx.createdAt);
        final bucketKey = state.range == AnalyticsRange.week7
            ? '${dt.month}/${dt.day}'
            : '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

        if (tx.type == 'sale') {
          sales += tx.totalAmount;
          profit += tx.profitAmount;
          branchSalesMap[tx.branchId] =
              (branchSalesMap[tx.branchId] ?? 0) + tx.totalAmount;
          bucketSales[bucketKey] = (bucketSales[bucketKey] ?? 0) + tx.totalAmount;

          for (final item in tx.items) {
            final prev = productMap[item.productId];
            productMap[item.productId] = (
              name: item.productName,
              qty: (prev?.qty ?? 0) + item.quantity,
              rev: (prev?.rev ?? 0) + item.quantity * item.unitPrice,
            );
          }
        } else if (tx.type == 'purchase') {
          purchases += tx.totalAmount;
          bucketPurchases[bucketKey] =
              (bucketPurchases[bucketKey] ?? 0) + tx.totalAmount;
        }
      }

      // Compute real inventory value from local branch_stock * product cost.
      double invValue = 0;
      final productById = {for (final p in products) p.id: p};
      final targetBranches = (!state.allBranches && activeBranchId != null)
          ? branches.where((b) => b.id == activeBranchId)
          : branches;
      for (final b in targetBranches) {
        final stock = await dao.getBranchStockMap(b.id);
        for (final entry in stock.entries) {
          final prod = productById[entry.key];
          if (prod != null) {
            invValue += entry.value * prod.costPrice;
          }
        }
      }

      final topProducts = productMap.entries
          .map(
            (e) => TopProductStat(
              productId: e.key,
              name: e.value.name,
              unitsSold: e.value.qty,
              revenue: e.value.rev,
            ),
          )
          .toList()
        ..sort((a, b) => b.revenue.compareTo(a.revenue));

      final branchComparison = branches
          .map(
            (b) => BranchSalesStat(
              branchName: b.name,
              totalSales: branchSalesMap[b.id] ?? 0,
            ),
          )
          .toList();

      final keys = {...bucketSales.keys, ...bucketPurchases.keys}.toList()
        ..sort();
      final trendBuckets = keys
          .map(
            (k) => TimeBucketStat(
              label: k,
              sales: bucketSales[k] ?? 0,
              purchases: bucketPurchases[k] ?? 0,
            ),
          )
          .toList();

      state = state.copyWith(
        totalSales: sales,
        totalPurchases: purchases,
        netProfit: profit,
        inventoryValue: invValue,
        topProducts: topProducts.take(5).toList(),
        branchComparison: branchComparison,
        trendBuckets: trendBuckets,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final analyticsControllerProvider =
    NotifierProvider<AnalyticsController, AnalyticsData>(
  AnalyticsController.new,
);
