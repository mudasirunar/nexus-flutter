/// User roles enforced via RBAC.
enum UserRole {
  admin('admin'),
  manager('manager'),
  employee('employee');

  const UserRole(this.value);
  final String value;

  static UserRole fromString(String? raw) {
    return UserRole.values.firstWhere(
      (r) => r.value == raw?.toLowerCase(),
      orElse: () => UserRole.employee,
    );
  }

  bool get canManageBranches => this == UserRole.admin;
  bool get canManageUsers => this == UserRole.admin;
  bool get canDeleteProducts => this == UserRole.admin;
  bool get canEditProducts =>
      this == UserRole.admin || this == UserRole.manager;
  bool get canAdjustStock =>
      this == UserRole.admin || this == UserRole.manager;
  bool get canTransferStock =>
      this == UserRole.admin || this == UserRole.manager;
  bool get canViewProfitAnalytics =>
      this == UserRole.admin || this == UserRole.manager;
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.assignedBranchId,
    required this.updatedAt,
  });

  final String uid;
  final String email;
  final String name;
  final UserRole role;
  final String? assignedBranchId;
  final int updatedAt;

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'email': email,
    'name': name,
    'role': role.value,
    'assigned_branch_id': assignedBranchId,
    'updated_at': updatedAt,
  };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    uid: map['uid'] as String,
    email: map['email'] as String,
    name: map['name'] as String,
    role: UserRole.fromString(map['role'] as String?),
    assignedBranchId: map['assigned_branch_id'] as String?,
    updatedAt: (map['updated_at'] as num).toInt(),
  );
}

class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.location,
    this.phone = '',
    this.isActive = true,
    required this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.syncStatus = 'pending',
    this.syncError,
  });

  final String id;
  final String name;
  final String location;
  final String phone;
  final bool isActive;
  final int updatedAt;
  final bool isDeleted;
  final int? deletedAt;
  final String syncStatus;
  final String? syncError;

  Map<String, dynamic> toSqlite() => {
    'id': id,
    'name': name,
    'location': location,
    'phone': phone,
    'is_active': isActive ? 1 : 0,
    'updated_at': updatedAt,
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt,
    'sync_status': syncStatus,
    'sync_error': syncError,
  };

  factory Branch.fromSqlite(Map<String, dynamic> m) => Branch(
    id: m['id'] as String,
    name: m['name'] as String,
    location: m['location'] as String,
    phone: (m['phone'] as String?) ?? '',
    isActive: (m['is_active'] as int? ?? 1) == 1,
    updatedAt: (m['updated_at'] as num).toInt(),
    isDeleted: (m['is_deleted'] as int? ?? 0) == 1,
    deletedAt: (m['deleted_at'] as num?)?.toInt(),
    syncStatus: (m['sync_status'] as String?) ?? 'synced',
    syncError: m['sync_error'] as String?,
  );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    this.barcode = '',
    this.category = 'General',
    required this.costPrice,
    required this.sellingPrice,
    this.lowStockThreshold = 5,
    this.imageUrl,
    required this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.syncStatus = 'pending',
    this.syncError,
  });

  final String id;
  final String name;
  final String sku;
  final String barcode;
  final String category;
  final double costPrice;
  final double sellingPrice;
  final int lowStockThreshold;
  final String? imageUrl;
  final int updatedAt;
  final bool isDeleted;
  final int? deletedAt;
  final String syncStatus;
  final String? syncError;

  Map<String, dynamic> toSqlite() => {
    'id': id,
    'name': name,
    'sku': sku,
    'barcode': barcode,
    'category': category,
    'cost_price': costPrice,
    'selling_price': sellingPrice,
    'low_stock_threshold': lowStockThreshold,
    'image_url': imageUrl,
    'updated_at': updatedAt,
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt,
    'sync_status': syncStatus,
    'sync_error': syncError,
  };

  factory Product.fromSqlite(Map<String, dynamic> m) => Product(
    id: m['id'] as String,
    name: m['name'] as String,
    sku: m['sku'] as String,
    barcode: (m['barcode'] as String?) ?? '',
    category: (m['category'] as String?) ?? 'General',
    costPrice: (m['cost_price'] as num).toDouble(),
    sellingPrice: (m['selling_price'] as num).toDouble(),
    lowStockThreshold: (m['low_stock_threshold'] as num?)?.toInt() ?? 5,
    imageUrl: m['image_url'] as String?,
    updatedAt: (m['updated_at'] as num).toInt(),
    isDeleted: (m['is_deleted'] as int? ?? 0) == 1,
    deletedAt: (m['deleted_at'] as num?)?.toInt(),
    syncStatus: (m['sync_status'] as String?) ?? 'synced',
    syncError: m['sync_error'] as String?,
  );
}

class TransactionItemModel {
  const TransactionItemModel({
    required this.id,
    required this.transactionId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
  });

  final String id;
  final String transactionId;
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double unitCost;

  Map<String, dynamic> toSqlite() => {
    'id': id,
    'transaction_id': transactionId,
    'product_id': productId,
    'product_name': productName,
    'quantity': quantity,
    'unit_price': unitPrice,
    'unit_cost': unitCost,
  };

  factory TransactionItemModel.fromSqlite(Map<String, dynamic> m) =>
      TransactionItemModel(
        id: m['id'] as String,
        transactionId: m['transaction_id'] as String,
        productId: m['product_id'] as String,
        productName: m['product_name'] as String,
        quantity: (m['quantity'] as num).toInt(),
        unitPrice: (m['unit_price'] as num).toDouble(),
        unitCost: (m['unit_cost'] as num).toDouble(),
      );
}

class BusinessTransaction {
  const BusinessTransaction({
    required this.id,
    required this.branchId,
    required this.type,
    required this.totalAmount,
    required this.profitAmount,
    this.notes = '',
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.syncStatus = 'pending',
    this.syncError,
    this.items = const [],
  });

  final String id;
  final String branchId;
  final String type; // 'sale' | 'purchase'
  final double totalAmount;
  final double profitAmount;
  final String notes;
  final String createdBy;
  final int createdAt;
  final int updatedAt;
  final bool isDeleted;
  final int? deletedAt;
  final String syncStatus;
  final String? syncError;
  final List<TransactionItemModel> items;

  Map<String, dynamic> toSqlite() => {
    'id': id,
    'branch_id': branchId,
    'type': type,
    'total_amount': totalAmount,
    'profit_amount': profitAmount,
    'notes': notes,
    'created_by': createdBy,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt,
    'sync_status': syncStatus,
    'sync_error': syncError,
  };

  factory BusinessTransaction.fromSqlite(
    Map<String, dynamic> m, {
    List<TransactionItemModel> items = const [],
  }) => BusinessTransaction(
    id: m['id'] as String,
    branchId: m['branch_id'] as String,
    type: m['type'] as String,
    totalAmount: (m['total_amount'] as num).toDouble(),
    profitAmount: (m['profit_amount'] as num?)?.toDouble() ?? 0,
    notes: (m['notes'] as String?) ?? '',
    createdBy: m['created_by'] as String,
    createdAt: (m['created_at'] as num).toInt(),
    updatedAt: (m['updated_at'] as num).toInt(),
    isDeleted: (m['is_deleted'] as int? ?? 0) == 1,
    deletedAt: (m['deleted_at'] as num?)?.toInt(),
    syncStatus: (m['sync_status'] as String?) ?? 'synced',
    syncError: m['sync_error'] as String?,
    items: items,
  );
}
