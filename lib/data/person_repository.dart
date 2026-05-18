import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/person.dart';

class PersonRepository {
  PersonRepository(this._client);
  final SupabaseClient _client;

  /// Strumień profili widocznych dla bieżącego usera (moich + udostępnionych mi).
  /// Slot 1: nasłuch zmian w tabeli `profiles` (RLS automatycznie filtruje).
  /// Slot 2: ładujemy `display_name` ownerów do wyświetlenia "udostępnione przez X".
  Stream<List<Person>> watch() {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .asyncMap(_attachOwnerNames);
  }

  Future<List<Person>> _attachOwnerNames(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const [];
    final ownerIds = rows.map((r) => r['owner_id'] as String).toSet().toList();
    final usersRows = await _client
        .from('users')
        .select('id, display_name')
        .inFilter('id', ownerIds);
    final nameMap = <String, String>{};
    for (final u in usersRows) {
      nameMap[u['id'] as String] = (u['display_name'] as String?) ?? '';
    }
    return rows
        .map((r) =>
            Person.fromRow(r, ownerName: nameMap[r['owner_id']] ?? ''))
        .toList();
  }

  Future<Person> create({required String name, String? photoUrl}) async {
    final ownerId = _client.auth.currentUser?.id;
    if (ownerId == null) throw StateError('Brak zalogowanego użytkownika.');
    final row = await _client
        .from('profiles')
        .insert({
          'owner_id': ownerId,
          'name': name.trim(),
          'photo_url': ?photoUrl,
        })
        .select()
        .single();
    final ownerName = await _ownerDisplayName(ownerId);
    return Person.fromRow(row, ownerName: ownerName);
  }

  Future<void> rename(String id, String name) async {
    await _client.from('profiles').update({
      'name': name.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> updatePhotoUrl(String id, String? photoUrl) async {
    await _client.from('profiles').update({
      'photo_url': photoUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('profiles').delete().eq('id', id);
  }

  /// Wypisz się z udostępnionego profilu (dla profili nie-własnych).
  Future<void> leaveShared(String profileId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('profile_shares')
        .delete()
        .eq('profile_id', profileId)
        .eq('user_id', userId);
  }

  Future<List<({String userId, String displayName})>> listShares(String profileId) async {
    final rows = await _client
        .from('profile_shares')
        .select('user_id, users(display_name)')
        .eq('profile_id', profileId);
    final out = <({String userId, String displayName})>[];
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      final users = m['users'] as Map?;
      out.add((
        userId: m['user_id'] as String,
        displayName: (users?['display_name'] as String?) ?? '',
      ));
    }
    return out;
  }

  Future<void> revokeShare(String profileId, String userId) async {
    await _client
        .from('profile_shares')
        .delete()
        .eq('profile_id', profileId)
        .eq('user_id', userId);
  }

  Future<String> _ownerDisplayName(String userId) async {
    final row = await _client
        .from('users')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    return (row?['display_name'] as String?) ?? '';
  }
}
