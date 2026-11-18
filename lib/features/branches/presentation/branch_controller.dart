import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../data/models/syncable_models.dart';
import '../../auth/presentation/auth_controller.dart';

const String _kActiveBranchKey = 'active_branch_id';

class BranchState {
  const BranchState({
    this.branches = const [],
    this.activeBranchId,
    this.summaries = const {},
    this.transfers = const [],
    this.isLoading = true,
    this.error,
  });

  final List<Branch> branches;
  final String? activeBranchId;
  final Map<String, ({int stockUnits, double salesTotal})> summaries;
  final List<StockTransfer> transfers;
  final bool isLoading;
  final String? error;

  Branch? get activeBranch {
    if (branches.isEmpty) return null;
    return branches.firstWhere(
      (b) => b.id == activeBranchId,
      orElse: () => branches.first,
    );
  }

  BranchState copyWith({
    List<Branch>? branches,
    String? activeBranchId,
    Map<String, ({int stockUnits, double salesTotal})>? summaries,
    List<StockTransfer>? transfers,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return BranchState(
      branches: branches ?? this.branches,
      activeBranchId: activeBranchId ?? this.activeBranchId,
      summaries: summaries ?? this.summaries,
      transfers: transfers ?? this.transfers,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BranchController extends Notifier<BranchState> {
  static const _uuid = Uuid();

  @override
  BranchState build() {
    Future.microtask(load);
    return const BranchState();
  }

  Future<void> load() async {
    try {
      final dao = await ref.read(nexusDaoProvider.future);
      final prefs = await SharedPreferences.getInstance();
      final branches = await dao.getBranches();
      final summaries = await dao.getBranchSummaries();
      final transfers = await dao.getStockTransfers();

      var activeId = prefs.getString(_kActiveBranchKey);
      if (activeId == null || !branches.any((b) => b.id == activeId)) {
        activeId = branches.isNotEmpty ? branches.first.id : null;
      }

      state = BranchState(
        branches: branches,
        activeBranchId: activeId,
        summaries: summaries,
        transfers: transfers,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Switches active branch cleanly offline or online without mixing data.
  Future<void> selectBranch(String branchId) async {
    state = state.copyWith(activeBranchId: branchId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveBranchKey, branchId);
  }

  Future<void> saveBranch({
    String? existingId,
    required String name,
    required String location,
    String phone = '',
  }) async {
    final dao = await ref.read(nexusDaoProvider.future);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = existingId ?? _uuid.v4();

    await dao.saveBranch(
      Branch(
        id: id,
        name: name.trim(),
        location: location.trim(),
        phone: phone.trim(),
        updatedAt: now,
        syncStatus: 'pending',
      ),
    );

    await load();
    if (state.activeBranchId == null) {
      await selectBranch(id);
    }
    _triggerBackgroundSync();
  }

  Future<void> deleteBranch(String branchId) async {
    final dao = await ref.read(nexusDaoProvider.future);
    final now = DateTime.now().millisecondsSinceEpoch;
    await dao.softDeleteRecord(table: 'branches', id: branchId, deletedAt: now);
    await load();
    _triggerBackgroundSync();
  }

  Future<void> transferStock({
    required String fromBranchId,
    required String toBranchId,
    required String productId,
    required int quantity,
    String note = '',
  }) async {
    if (fromBranchId == toBranchId) {
      throw ArgumentError('Source and destination branches must be different.');
    }
    if (quantity <= 0) {
      throw ArgumentError('Transfer quantity must be greater than zero.');
    }

    final dao = await ref.read(nexusDaoProvider.future);
    final userId = ref.read(authControllerProvider).user?.uid ?? 'unknown';
    final now = DateTime.now().millisecondsSinceEpoch;

    final transfer = StockTransfer(
      id: _uuid.v4(),
      fromBranchId: fromBranchId,
      toBranchId: toBranchId,
      productId: productId,
      quantity: quantity,
      note: note.trim(),
      createdBy: userId,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );

    await dao.executeStockTransfer(
      transfer: transfer,
      outMovementId: _uuid.v4(),
      inMovementId: _uuid.v4(),
    );

    await load();
    _triggerBackgroundSync();
  }

  void _triggerBackgroundSync() {
    ref.read(syncControllerProvider.notifier).refreshQueueCounts();
    final online = ref.read(isOnlineProvider).value ?? false;
    if (online) {
      ref.read(syncControllerProvider.notifier).syncNow();
    }
  }
}

final branchControllerProvider = NotifierProvider<BranchController, BranchState>(
  BranchController.new,
);
