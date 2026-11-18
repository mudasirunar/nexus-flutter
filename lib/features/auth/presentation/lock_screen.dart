import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _message;

  @override
  void initState() {
    super.initState();
    Future.microtask(_unlock);
  }

  Future<void> _unlock() async {
    final ok =
        await ref.read(authControllerProvider.notifier).unlockWithBiometrics();
    if (!ok && mounted) {
      setState(() {
        _message = 'Biometric verification cancelled or unavailable.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fingerprint,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'NEXUS Locked',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      user.email,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _unlock,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Unlock with Biometrics'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Sign Out & Use Password'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
