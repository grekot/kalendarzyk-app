import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cycle_repository.dart';
import 'person_repository.dart';

const String legacyHiveBox = 'box_cycles';
const String legacyStartsKey = 'starts';
const String legacyPersonsKey = 'persons';
const String legacyStartsKeyPrefix = 'starts_';

/// Migracja lokalnej bazy Hive (poprzednia wersja apki) do Supabase.
/// Wywołać raz, po sign-in. Idempotentna — po sukcesie czyści Hive box.
class MigrationService {
  MigrationService(this._client, this._personRepo, this._cycleRepo);

  final SupabaseClient _client;
  final PersonRepository _personRepo;
  final CycleRepository _cycleRepo;

  /// Próbuje wczytać starą bazę z Hive i wgrać dane do Supabase
  /// jako profile bieżącego usera. Zwraca true jeśli coś zostało zmigrowane.
  Future<bool> migrateIfNeeded() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    await Hive.initFlutter();
    if (!await Hive.boxExists(legacyHiveBox)) return false;
    final box = await Hive.openBox(legacyHiveBox);

    try {
      var migratedSomething = false;

      // 1. Profile (klucz 'persons')
      final personsRaw = box.get(legacyPersonsKey);
      if (personsRaw is List && personsRaw.isNotEmpty) {
        for (final p in personsRaw.whereType<Map>()) {
          final localId = p['id']?.toString();
          final name = (p['name'] as String?)?.trim() ?? 'Bez nazwy';
          if (localId == null) continue;
          final created = await _personRepo.create(name: name);
          final startsList =
              box.get('$legacyStartsKeyPrefix$localId') as List? ?? const [];
          for (final s in startsList.whereType<String>()) {
            try {
              await _cycleRepo.addStart(created.id, DateTime.parse(s));
            } catch (_) {}
          }
          migratedSomething = true;
        }
      } else {
        // 2. Legacy v0 — pojedyncza lista 'starts' bez profili
        final startsRaw = box.get(legacyStartsKey);
        if (startsRaw is List && startsRaw.isNotEmpty) {
          final created = await _personRepo.create(name: 'Osoba 1');
          for (final s in startsRaw.whereType<String>()) {
            try {
              await _cycleRepo.addStart(created.id, DateTime.parse(s));
            } catch (_) {}
          }
          migratedSomething = true;
        }
      }

      if (migratedSomething) {
        await box.clear();
        await box.close();
        await Hive.deleteBoxFromDisk(legacyHiveBox);
      } else {
        await box.close();
      }

      return migratedSomething;
    } catch (e) {
      // Nie udało się — zostaw Hive nietknięty, kolejny start spróbuje ponownie.
      try {
        await box.close();
      } catch (_) {}
      rethrow;
    }
  }
}
