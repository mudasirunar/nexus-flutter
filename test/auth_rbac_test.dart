import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/data/models/syncable_models.dart';

void main() {
  group('RBAC UserRole permissions', () {
    test('Admin has all permissions', () {
      const role = UserRole.admin;
      expect(role.canManageBranches, isTrue);
      expect(role.canManageUsers, isTrue);
      expect(role.canDeleteProducts, isTrue);
      expect(role.canEditProducts, isTrue);
      expect(role.canAdjustStock, isTrue);
      expect(role.canTransferStock, isTrue);
      expect(role.canViewProfitAnalytics, isTrue);
    });

    test('Manager has operational & analytics permissions but not branch/user admin', () {
      const role = UserRole.manager;
      expect(role.canManageBranches, isFalse);
      expect(role.canManageUsers, isFalse);
      expect(role.canDeleteProducts, isFalse);
      expect(role.canEditProducts, isTrue);
      expect(role.canAdjustStock, isTrue);
      expect(role.canTransferStock, isTrue);
      expect(role.canViewProfitAnalytics, isTrue);
    });

    test('Employee has sales-only operational access', () {
      const role = UserRole.employee;
      expect(role.canManageBranches, isFalse);
      expect(role.canManageUsers, isFalse);
      expect(role.canDeleteProducts, isFalse);
      expect(role.canEditProducts, isFalse);
      expect(role.canAdjustStock, isFalse);
      expect(role.canTransferStock, isFalse);
      expect(role.canViewProfitAnalytics, isFalse);
    });

    test('UserRole.fromString defaults safely to employee for unknown values', () {
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('MANAGER'), UserRole.manager);
      expect(UserRole.fromString('unknown'), UserRole.employee);
      expect(UserRole.fromString(null), UserRole.employee);
    });
  });
}
