import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Controls whether the app connects to the local Firebase Emulator Suite.
///
/// Defaults to `true` during development. Pass
/// `--dart-define=USE_FIREBASE_EMULATOR=false` (or flip in Phase 7) to connect
/// to the live Firebase project.
const bool kUseFirebaseEmulator = bool.fromEnvironment(
  'USE_FIREBASE_EMULATOR',
  defaultValue: true,
);

/// Optional override for physical devices on the same LAN, e.g.:
/// `--dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10`
const String _kEmulatorHostOverride = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: '',
);

/// Default emulator project options used when running against the local
/// Firebase Emulator Suite before real `firebase_options.dart` is wired in Phase 7.
const FirebaseOptions kLocalEmulatorFirebaseOptions = FirebaseOptions(
  apiKey: 'local-emulator-api-key',
  appId: '1:000000000000:android:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'nexus-local-dev',
);

/// Resolves the appropriate host for the Firebase Emulator Suite.
String resolveEmulatorHost() {
  if (_kEmulatorHostOverride.isNotEmpty) {
    return _kEmulatorHostOverride;
  }
  if (!kIsWeb && Platform.isAndroid) {
    return '10.0.2.2';
  }
  return 'localhost';
}

/// Configures Firebase Auth and Cloud Firestore to point at the local emulators
/// when [kUseFirebaseEmulator] is enabled.
Future<void> configureFirebaseEmulatorsIfNeeded() async {
  if (!kUseFirebaseEmulator) return;

  final host = resolveEmulatorHost();
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

  // Disable Firestore's own offline cache since NEXUS uses SQLite (sqflite)
  // as the single local source of truth with explicit LWW + Delete-Wins sync.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
    sslEnabled: false,
  );
}
