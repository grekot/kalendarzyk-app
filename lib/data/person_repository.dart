import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/person.dart';

class ShareEntry {
  ShareEntry({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final ShareRole role;
}

class PersonRepository {
  PersonRepository(this._client);
  final SupabaseClient _client;

  /// Strumień profili widocznych dla bieżącego usera (moich + udostępnionych mi).
  /// Doładowuje display names ownerów i rolę bieżącego usera w każdym profilu.
  Stream<List<Person>> watch() {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .asyncMap(_enrich);
  }

  Future<List<Person>> _enrich(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const [];
    final me = _client.auth.currentUser?.id;

    final ownerIds =
        rows.map((r) => r['owner_id'] as String).toSet().toList();
    final usersRows = await _client
        .from('users')
        .select('id, display_name')
        .inFilter('id', ownerIds);
    final nameMap = <String, String>{};
    for (final u in usersRows) {
      nameMap[u['id'] as String] = (u['display_name'] as String?) ?? '';
    }

    // Pobierz role bieżącego usera dla wszystkich widocznych profili
    // (tylko gdy ja nie jestem ownerem — wtedy w tabeli profile_shares jest wiersz).
    Map<String, ShareRole> myRoles = {};
    if (me != null) {
      final profileIds = rows.map((r) => r['id'] as String).toList();
      final shareRows = await _client
          .from('profile_shares')
          .select('profile_id, role')
          .eq('user_id', me)
          .inFilter('profile_id', profileIds);
      for (final s in shareRows) {
        final pid = s['profile_id'] as String;
        final role = Person.parseRole(s['role'] as String?);
        if (role != null) myRoles[pid] = role;
      }
    }

    return rows
        .map((r) => Person.fromRow(
              r,
              ownerName: nameMap[r['owner_id']] ?? '',
              myRole: myRoles[r['id'] as String],
            ))
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

  Future<void> setOvulationUncertainty(String id, int value) async {
    final clamped = value.clamp(
      Person.minOvulationUncertainty,
      Person.maxOvulationUncertainty,
    );
    await _client.from('profiles').update({
      'ovulation_uncertainty': clamped,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('profiles').delete().eq('id', id);
  }

  Future<void> leaveShared(String profileId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('profile_shares')
        .delete()
        .eq('profile_id', profileId)
        .eq('user_id', userId);
  }

  Future<List<ShareEntry>> listShares(String profileId) async {
    final rows = await _client
        .from('profile_shares')
        .select('user_id, role, users(display_name)')
        .eq('profile_id', profileId);
    final out = <ShareEntry>[];
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      final users = m['users'] as Map?;
      out.add(ShareEntry(
        userId: m['user_id'] as String,
        displayName: (users?['display_name'] as String?) ?? '',
        role: Person.parseRole(m['role'] as String?) ?? ShareRole.editor,
      ));
    }
    return out;
  }

  Future<void> updateShareRole(
    String profileId,
    String userId,
    ShareRole role,
  ) async {
    await _client
        .from('profile_shares')
        .update({'role': Person.roleToSql(role)})
        .eq('profile_id', profileId)
        .eq('user_id', userId);
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
