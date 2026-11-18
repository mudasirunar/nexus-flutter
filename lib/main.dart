import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/firebase_emulator_config.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/lock_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'shared/widgets/app_shell.dart';
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

class NexusApp extends ConsumerWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) =>
          ref.read(authControllerProvider.notifier).recordUserActivity(),
      child: MaterialApp(
        title: 'NEXUS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: switch (authState.status) {
          AuthStatus.loading => const Scaffold(
            body: AppLoadingView(message: 'Restoring session...'),
          ),
          AuthStatus.unauthenticated => const LoginScreen(),
          AuthStatus.locked => const LockScreen(),
          AuthStatus.authenticated => const AppShell(),
        },
      ),
    );
  }
}
