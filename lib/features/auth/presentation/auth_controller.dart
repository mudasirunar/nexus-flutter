import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../data/models/syncable_models.dart';
import '../data/auth_repository.dart';

enum AuthStatus { loading, unauthenticated, locked, authenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.loading,
    this.user,
    this.biometricEnabled = false,
    this.inactivityMinutes = 5,
    this.error,
    this.isBusy = false,
  });

  final AuthStatus status;
  final UserProfile? user;
  final bool biometricEnabled;
  final int inactivityMinutes;
  final String? error;
  final bool isBusy;

  AuthState copyWith({
    AuthStatus? status,
    UserProfile? user,
    bool clearUser = false,
    bool? biometricEnabled,
    int? inactivityMinutes,
    String? error,
    bool clearError = false,
    bool? isBusy,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      inactivityMinutes: inactivityMinutes ?? this.inactivityMinutes,
      error: clearError ? null : (error ?? this.error),
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(),
);

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final dao = await ref.watch(nexusDaoProvider.future);
  return AuthRepository(dao: dao);
});

class AuthController extends Notifier<AuthState> {
  Timer? _inactivityTimer;

  @override
  AuthState build() {
    ref.onDispose(() => _inactivityTimer?.cancel());
    Future.microtask(_restore);
    return const AuthState(status: AuthStatus.loading);
  }

  Future<void> _restore() async {
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      final user = await repo.restoreSession();
      final bioEnabled = await repo.isBiometricEnabled();
      final minutes = await repo.getInactivityMinutes();

      if (user == null) {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          biometricEnabled: bioEnabled,
          inactivityMinutes: minutes,
        );
        return;
      }

      state = AuthState(
        status: bioEnabled ? AuthStatus.locked : AuthStatus.authenticated,
        user: user,
        biometricEnabled: bioEnabled,
        inactivityMinutes: minutes,
      );
      if (!bioEnabled) {
        _resetInactivityTimer();
      }
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
    }
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      final user = await repo.signIn(email: email, password: password);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isBusy: false,
      );
      _resetInactivityTimer();
      return true;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isBusy: false,
        error: e.message ?? 'Sign-in failed (${e.code}).',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isBusy: false, error: e.toString());
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      final user = await repo.register(
        name: name,
        email: email,
        password: password,
        role: role,
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isBusy: false,
      );
      _resetInactivityTimer();
      return true;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isBusy: false,
        error: e.message ?? 'Registration failed (${e.code}).',
      );
      return false;
    } catch (e) {
      state = state.copyWith(isBusy: false, error: e.toString());
      return false;
    }
  }

  Future<void> signOut() async {
    _inactivityTimer?.cancel();
    final repo = await ref.read(authRepositoryProvider.future);
    await repo.signOut();
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      clearUser: true,
      clearError: true,
    );
  }

  Future<bool> unlockWithBiometrics() async {
    final bio = ref.read(biometricServiceProvider);
    final ok = await bio.authenticate();
    if (ok) {
      state = state.copyWith(status: AuthStatus.authenticated, clearError: true);
      _resetInactivityTimer();
    }
    return ok;
  }

  void lockSession() {
    if (state.status == AuthStatus.authenticated && state.biometricEnabled) {
      _inactivityTimer?.cancel();
      state = state.copyWith(status: AuthStatus.locked);
    }
  }

  void recordUserActivity() {
    if (state.status == AuthStatus.authenticated) {
      _resetInactivityTimer();
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final repo = await ref.read(authRepositoryProvider.future);
    await repo.setBiometricEnabled(enabled);
    state = state.copyWith(biometricEnabled: enabled);
  }

  Future<void> setInactivityMinutes(int minutes) async {
    final repo = await ref.read(authRepositoryProvider.future);
    await repo.setInactivityMinutes(minutes);
    state = state.copyWith(inactivityMinutes: minutes);
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (state.status != AuthStatus.authenticated) return;
    _inactivityTimer = Timer(
      Duration(minutes: state.inactivityMinutes),
      () {
        // Auto-logout after inactivity per PRD & PDF security requirement.
        signOut();
      },
    );
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
