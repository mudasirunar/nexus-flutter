import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Subtle animated shimmer placeholder box that adapts to Light & Dark themes.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final highlightColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final slide = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(slide - 0.8, 0),
              end: Alignment(slide + 0.8, 0),
              colors: [baseColor, highlightColor, baseColor],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton layout matching the Analytics Dashboard (KPI grid + charts + list).
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const Row(
          children: [
            ShimmerBox(width: 180, height: 38, borderRadius: 10),
            Spacer(),
            ShimmerBox(width: 110, height: 38, borderRadius: 10),
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
              children: List.generate(
                4,
                (_) => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ShimmerBox(width: 80, height: 12),
                        SizedBox(height: 10),
                        ShimmerBox(width: 100, height: 22),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 160, height: 16),
                SizedBox(height: AppSpacing.lg),
                ShimmerBox(height: 180, borderRadius: 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 180, height: 16),
                SizedBox(height: AppSpacing.lg),
                ShimmerBox(height: 150, borderRadius: 10),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Skeleton list matching Inventory, Transactions, and Branches cards.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    this.itemCount = 6,
    this.compact = false,
  });

  final int itemCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: compact,
      physics: compact ? const NeverScrollableScrollPhysics() : null,
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(AppSpacing.lg),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, _) {
        if (compact) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(width: 140, height: 13),
                      SizedBox(height: 6),
                      ShimmerBox(width: 90, height: 10),
                    ],
                  ),
                ),
                ShimmerBox(width: 40, height: 18),
              ],
            ),
          );
        }
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                ShimmerBox(width: 44, height: 44, borderRadius: 8),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(width: 160, height: 14),
                      SizedBox(height: 8),
                      ShimmerBox(width: 110, height: 11),
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                ShimmerBox(width: 56, height: 28, borderRadius: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
