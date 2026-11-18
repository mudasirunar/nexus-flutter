import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/firebase_emulator_config.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'shared/widgets/app_state_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: kUseFirebaseEmulator ? kLocalEmulatorFirebaseOptions : null,
  );
  await configureFirebaseEmulatorsIfNeeded();
  await NotificationService.instance.initialize();

  runApp(const ProviderScope(child: NexusApp()));
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXUS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _PhaseOneBootstrapScreen(),
    );
  }
}

class _PhaseOneBootstrapScreen extends StatelessWidget {
  const _PhaseOneBootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NEXUS')),
      body: Column(
        children: [
          const OfflineBanner(isOffline: false),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXUS Business Management',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        kUseFirebaseEmulator
                            ? 'Connected to Local Firebase Emulator Suite (${resolveEmulatorHost()})'
                            : 'Connected to Live Firebase',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const SyncStatusBadge(status: SyncRecordStatus.synced),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
