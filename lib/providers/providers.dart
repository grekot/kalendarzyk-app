import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_service.dart';
import '../data/cycle_repository.dart';
import '../data/invite_repository.dart';
import '../data/person_repository.dart';
import '../data/storage_service.dart';
import '../models/person.dart';

// ─── client + serwisy ────────────────────────────────────────────

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});

final personRepositoryProvider = Provider<PersonRepository>((ref) {
  return PersonRepository(ref.watch(supabaseClientProvider));
});

final cycleRepositoryProvider = Provider<CycleRepository>((ref) {
  return CycleRepository(ref.watch(supabaseClientProvider));
});

final inviteRepositoryProvider = Provider<InviteRepository>((ref) {
  return InviteRepository(ref.watch(supabaseClientProvider));
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(supabaseClientProvider));
});

// ─── stan użytkownika ────────────────────────────────────────────

final currentUserIdProvider = StreamProvider<String?>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth.authChanges.map((s) => s.session?.user.id);
});

final displayNameProvider = FutureProvider<String>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.watch(authServiceProvider).getDisplayName();
});

final defaultProfileIdProvider = FutureProvider<String?>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.watch(authServiceProvider).getDefaultProfileId();
});

// ─── lista profili (strumień, RLS filtruje) ──────────────────────

final personsProvider = StreamProvider<List<Person>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(personRepositoryProvider).watch();
});

// ─── aktywny profil ──────────────────────────────────────────────
//
// activePersonId — wybór bieżącej sesji. Inicjalizowany przez
// `defaultProfileIdProvider` w UI (np. w AuthGate / HomeScreen).

final activePersonIdProvider = StateProvider<String?>((ref) => null);

final activePersonProvider = Provider<Person?>((ref) {
  final id = ref.watch(activePersonIdProvider);
  final persons = ref.watch(personsProvider).valueOrNull;
  if (id == null || persons == null) return null;
  for (final p in persons) {
    if (p.id == id) return p;
  }
  return persons.isEmpty ? null : persons.first;
});

// ─── cykle aktywnego profilu ─────────────────────────────────────

final cyclesProvider = StreamProvider<List<DateTime>>((ref) {
  final id = ref.watch(activePersonIdProvider);
  if (id == null) return const Stream<List<DateTime>>.empty();
  return ref.watch(cycleRepositoryProvider).watch(id);
});

// ─── ustawienia lokalne (per urządzenie, shared_preferences) ────

class ShowFertilityNotifier extends StateNotifier<bool> {
  ShowFertilityNotifier() : super(true) {
    _load();
  }

  static const String _key = 'show_fertility';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_key);
    if (v != null && v != state) state = v;
  }

  Future<void> set(bool value) async {
    if (value == state) return;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  Future<void> toggle() => set(!state);
}

/// Flag wł/wył wyświetlanie okna płodnego i owulacji w UI.
/// Per-urządzenie (lokalne `SharedPreferences`), domyślnie włączone.
final showFertilityProvider =
    StateNotifierProvider<ShowFertilityNotifier, bool>(
  (ref) => ShowFertilityNotifier(),
);
