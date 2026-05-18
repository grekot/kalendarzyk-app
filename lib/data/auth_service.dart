import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService(this._client);
  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  bool get isSignedIn => _client.auth.currentUser != null;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<void> ensureSignedIn() async {
    if (_client.auth.currentUser != null) return;
    await _client.auth.signInAnonymously();
  }

  Future<String> getDisplayName() async {
    final id = currentUserId;
    if (id == null) return '';
    final row = await _client
        .from('users')
        .select('display_name')
        .eq('id', id)
        .maybeSingle();
    return (row?['display_name'] as String?)?.trim() ?? '';
  }

  Future<void> setDisplayName(String name) async {
    final id = currentUserId;
    if (id == null) throw StateError('Brak zalogowanego użytkownika.');
    await _client.from('users').upsert({
      'id': id,
      'display_name': name.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String?> getDefaultProfileId() async {
    final id = currentUserId;
    if (id == null) return null;
    final row = await _client
        .from('users')
        .select('default_profile_id')
        .eq('id', id)
        .maybeSingle();
    return row?['default_profile_id'] as String?;
  }

  Future<void> setDefaultProfileId(String? profileId) async {
    final id = currentUserId;
    if (id == null) return;
    await _client.from('users').update({
      'default_profile_id': profileId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }
}
