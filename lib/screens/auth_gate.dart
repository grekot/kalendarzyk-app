import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'sign_in_screen.dart';

/// Bramka uruchomieniowa:
///   1. Brak sesji → SignInScreen (Google OAuth).
///   2. Sesja jest, ale displayName pusty → OnboardingScreen.
///   3. Wszystko gotowe → HomeScreen.
///
/// Po zmianach auth (sign-in / sign-out) `currentUserIdProvider`
/// emituje nową wartość, AuthGate sam się przerenderuje.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserIdProvider);

    return userAsync.when(
      loading: () => const _Splash(),
      error: (e, _) => _ErrorScreen(error: e),
      data: (userId) {
        if (userId == null) {
          return const SignInScreen();
        }
        final displayNameAsync = ref.watch(displayNameProvider);
        return displayNameAsync.when(
          loading: () => const _Splash(),
          error: (e, _) => _ErrorScreen(error: e),
          data: (name) {
            if (name.trim().isEmpty) {
              return const OnboardingScreen();
            }
            return const HomeScreen();
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off,
                    size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                const Text(
                  'Nie udało się połączyć z chmurą.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sprawdź połączenie z internetem i spróbuj ponownie.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
