import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

class InviteRepository {
  InviteRepository(this._client);
  final SupabaseClient _client;

  static const Duration ttl = Duration(minutes: 10);

  /// Tworzy 6-cyfrowy kod parowania dla profilu. Zwraca kod.
  /// Stary niewygasły kod dla tego profilu (jeśli istnieje) zostaje nadpisany
  /// — w praktyce kod jest losowy więc kolizji nie będzie, ale dla pewności
  /// retryujemy raz przy konflikcie primary key.
  Future<({String code, DateTime expiresAt})> createInvite(String profileId) async {
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
          'expires_at': expiresAt.toIso8601String(),
        });
        return (code: code, expiresAt: expiresAt);
      } on PostgrestException catch (e) {
        // 23505 = unique_violation (kolizja kodu)
        if (e.code == '23505') continue;
        rethrow;
      }
    }
    throw StateError('Nie udało się wygenerować unikalnego kodu.');
  }

  /// Realizuje invite — dopisuje bieżącego usera do profile_shares
  /// i kasuje invite. Zwraca id profilu.
  Future<String> redeemInvite(String code) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Brak zalogowanego użytkownika.');
    final cleaned = code.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final row = await _client
        .from('invites')
        .select('profile_id, expires_at')
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
    await _client.from('profile_shares').upsert({
      'profile_id': profileId,
      'user_id': userId,
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
