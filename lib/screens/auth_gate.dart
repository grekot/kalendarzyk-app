import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/migration_service.dart';
import '../providers/providers.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

/// Bramka uruchomieniowa:
///   1. Anonymous sign-in (jeśli brak sesji).
///   2. Migracja Hive → Supabase (jednorazowa).
///   3. Onboarding: jeśli displayName pusty.
///   4. HomeScreen.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  Future<void>? _bootstrap;

  @override
  Widget build(BuildContext context) {
    _bootstrap ??= _initialize();
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Splash();
        }
        if (snap.hasError) {
          return _ErrorScreen(error: snap.error!);
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

  Future<void> _initialize() async {
    final auth = ref.read(authServiceProvider);
    await auth.ensureSignedIn();
    final migration = MigrationService(
      ref.read(supabaseClientProvider),
      ref.read(personRepositoryProvider),
      ref.read(cycleRepositoryProvider),
    );
    try {
      await migration.migrateIfNeeded();
    } catch (_) {
      // Migracja best-effort — w razie czego dane lokalne zostają w Hive.
    }
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
