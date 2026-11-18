import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/local/daos/nexus_dao.dart';
import '../../../data/models/syncable_models.dart';

const String _kCachedUidKey = 'cached_auth_uid';
const String _kBiometricEnabledKey = 'biometric_lock_enabled';
const String _kInactivityMinutesKey = 'inactivity_timeout_minutes';

/// Handles Firebase Email/Password authentication, local offline session
/// caching, RBAC profile resolution, and mock forgot-password flow.
class AuthRepository {
  AuthRepository({
    required this.dao,
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _auth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final NexusDao dao;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Restores the currently signed-in user from FirebaseAuth or local SQLite
  /// cache (enabling offline app launches).
  Future<UserProfile?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final firebaseUser = _auth.currentUser;
    final uid = firebaseUser?.uid ?? prefs.getString(_kCachedUidKey);
    if (uid == null || uid.isEmpty) return null;

    // Try local cache first for instant offline-first startup.
    final localProfile = await dao.getUser(uid);
    if (localProfile != null) {
      // Refresh from Firestore in the background if online.
      _refreshProfileFromRemote(uid);
      return localProfile;
    }

    return _fetchAndCacheProfile(uid, fallbackEmail: firebaseUser?.email ?? '');
  }

  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Unable to sign in.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCachedUidKey, user.uid);

    final profile = await _fetchAndCacheProfile(
      user.uid,
      fallbackEmail: user.email ?? email.trim(),
    );
    if (profile == null) {
      final fallback = UserProfile(
        uid: user.uid,
        email: user.email ?? email.trim(),
        name: user.displayName ?? email.split('@').first,
        role: UserRole.employee,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveProfileBoth(fallback);
      return fallback;
    }
    return profile;
  }

  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'registration-failed',
        message: 'Unable to create account.',
      );
    }

    await user.updateDisplayName(name.trim());

    final profile = UserProfile(
      uid: user.uid,
      email: email.trim(),
      name: name.trim(),
      role: role,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCachedUidKey, user.uid);

    await _saveProfileBoth(profile);
    return profile;
  }

  /// Mock forgot-password flow (per project requirements: no custom backend/SMTP).
  Future<void> mockSendPasswordReset({required String email}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw FormatException('Please enter a valid email address.');
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedUidKey);
    await _auth.signOut();
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricEnabledKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabledKey, enabled);
  }

  Future<int> getInactivityMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kInactivityMinutesKey) ?? 5;
  }

  Future<void> setInactivityMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kInactivityMinutesKey, minutes);
  }

  Future<void> _saveProfileBoth(UserProfile profile) async {
    await dao.upsertUser(profile);
    try {
      await _firestore.collection('users').doc(profile.uid).set({
        'uid': profile.uid,
        'email': profile.email,
        'name': profile.name,
        'role': profile.role.value,
        'assignedBranchId': profile.assignedBranchId,
        'updatedAt': profile.updatedAt,
      }, SetOptions(merge: true));
    } catch (_) {
      // Offline: local SQLite cache still preserves profile.
    }
  }

  Future<void> _refreshProfileFromRemote(String uid) async {
    try {
      await _fetchAndCacheProfile(uid);
    } catch (_) {
      // Ignore when offline.
    }
  }

  Future<UserProfile?> _fetchAndCacheProfile(
    String uid, {
    String fallbackEmail = '',
  }) async {
    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      if (!snap.exists || snap.data() == null) return null;
      final data = snap.data()!;
      final profile = UserProfile(
        uid: uid,
        email: (data['email'] as String?) ?? fallbackEmail,
        name: (data['name'] as String?) ?? 'NEXUS User',
        role: UserRole.fromString(data['role'] as String?),
        assignedBranchId: data['assignedBranchId'] as String?,
        updatedAt: (data['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      );
      await dao.upsertUser(profile);
      return profile;
    } catch (_) {
      return dao.getUser(uid);
    }
  }
}
