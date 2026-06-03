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

  /// Realizuje invite atomicznie przez RPC `redeem_invite` (SECURITY DEFINER):
  /// sprawdza expiry, wstawia bieżącego usera do profile_shares z rolą z invite,
  /// kasuje invite. Zwraca id profilu.
  Future<String> redeemInvite(String code) async {
    if (_client.auth.currentUser == null) {
      throw StateError('Brak zalogowanego użytkownika.');
    }
    final cleaned = code.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    try {
      final result = await _client.rpc(
        'redeem_invite',
        params: {'p_code': cleaned},
      );
      if (result == null) {
        throw const FormatException('Nieprawidłowy kod.');
      }
      return result.toString();
    } on PostgrestException catch (e) {
      // SQLSTATE z funkcji: P0001 invalid_code, P0002 expired_code, 28000 not_authenticated
      final msg = e.message;
      if (msg.contains('invalid_code')) {
        throw const FormatException('Nieprawidłowy kod.');
      }
      if (msg.contains('expired_code')) {
        throw const FormatException('Kod wygasł. Poproś o nowy.');
      }
      if (msg.contains('not_authenticated')) {
        throw StateError('Brak zalogowanego użytkownika.');
      }
      rethrow;
    }
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
