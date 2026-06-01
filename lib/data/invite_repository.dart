import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/person.dart';

class InviteRepository {
  InviteRepository(this._client);
  final SupabaseClient _client;

  static const Duration ttl = Duration(minutes: 10);

  /// Tworzy 6-cyfrowy kod parowania dla profilu z określoną rolą.
  Future<({String code, DateTime expiresAt, ShareRole role})> createInvite(
    String profileId, {
    required ShareRole role,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Brak zalogowanego użytkownika.');
    final expiresAt = DateTime.now().toUtc().add(ttl);
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _generateCode();
      try {
        await _client.from('invites').insert({
          'code': code,
          'profile_id': profileId,
          'created_by': userId,
          'role': Person.roleToSql(role),
          'expires_at': expiresAt.toIso8601String(),
        });
        return (code: code, expiresAt: expiresAt, role: role);
      } on PostgrestException catch (e) {
        // 23505 = unique_violation (kolizja kodu) — retry z nowym kodem
        if (e.code == '23505') continue;
        rethrow;
      }
    }
    throw StateError('Nie udało się wygenerować unikalnego kodu.');
  }

  /// Realizuje invite — dopisuje bieżącego usera do profile_shares z rolą z invite
  /// i kasuje invite. Zwraca id profilu.
  Future<String> redeemInvite(String code) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Brak zalogowanego użytkownika.');
    final cleaned = code.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final row = await _client
        .from('invites')
        .select('profile_id, expires_at, role')
        .eq('code', cleaned)
        .maybeSingle();
    if (row == null) {
      throw const FormatException('Nieprawidłowy kod.');
    }
    final expiresAt = DateTime.parse(row['expires_at'] as String);
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      throw const FormatException('Kod wygasł. Poproś o nowy.');
    }
    final profileId = row['profile_id'] as String;
    final role = Person.parseRole(row['role'] as String?) ?? ShareRole.editor;
    await _client.from('profile_shares').upsert({
      'profile_id': profileId,
      'user_id': userId,
      'role': Person.roleToSql(role),
    });
    await _client.from('invites').delete().eq('code', cleaned);
    return profileId;
  }

  String _generateCode() {
    final rnd = Random.secure();
    const chars = '0123456789';
    final sb = StringBuffer();
    for (var i = 0; i < 6; i++) {
      sb.write(chars[rnd.nextInt(chars.length)]);
    }
    return sb.toString();
  }
}
