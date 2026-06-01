import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService(this._client);
  final SupabaseClient _client;

  static const String mobileRedirectUrl = 'kalendarzyk://login-callback';
  static const int desktopCallbackPort = 8765;
  static const String desktopRedirectUrl =
      'http://localhost:$desktopCallbackPort/callback';

  String? get currentUserId => _client.auth.currentUser?.id;

  bool get isSignedIn => _client.auth.currentUser != null;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  String? get googleEmail => _client.auth.currentUser?.email;

  String? get googleName {
    final meta = _client.auth.currentUser?.userMetadata;
    if (meta == null) return null;
    final name = meta['full_name'] ?? meta['name'];
    return name?.toString();
  }

  /// Uruchamia OAuth flow Google → Supabase → callback do apki.
  /// Na Androidzie/iOS — deep link `kalendarzyk://login-callback`.
  /// Na desktopie (Win/Mac/Linux) — lokalny HTTP server na `localhost:8765`.
  Future<void> signInWithGoogle() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: mobileRedirectUrl,
      );
      // SDK obsługuje deep link automatycznie; sesja pojawi się przez
      // onAuthStateChange gdy callback wróci.
    } else {
      await _signInWithGoogleDesktop();
    }
  }

  Future<void> _signInWithGoogleDesktop() async {
    HttpServer? server;
    final completer = Completer<String>();
    try {
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        desktopCallbackPort,
      );

      // Listener na callback z Supabase.
      server.listen((request) async {
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error_description'] ??
            request.uri.queryParameters['error'];

        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('''
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="utf-8">
  <title>Kalendarzyk</title>
  <style>
    body { font-family: -apple-system, "Segoe UI", sans-serif;
           background:#fff5f8; color:#3b001a; text-align:center;
           padding:80px 20px; margin:0; }
    h1 { font-size: 28px; color:#C2185B; }
    p { font-size: 16px; color:#5a2740; }
  </style>
</head>
<body>
  <h1>${code != null ? "✓ Zalogowano" : "Błąd logowania"}</h1>
  <p>${code != null ? "Możesz zamknąć tę kartę i wrócić do aplikacji." : (error ?? "Spróbuj jeszcze raz.")}</p>
</body>
</html>
''');
        await request.response.close();

        if (!completer.isCompleted) {
          if (code != null) {
            completer.complete(code);
          } else {
            completer.completeError(error ?? 'Brak kodu w odpowiedzi.');
          }
        }
      });

      // Uruchamiamy OAuth flow przez SDK — wewnętrznie generuje PKCE verifier
      // i opens browser. Na desktop launchUrl używa systemowej przeglądarki.
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: desktopRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      // Czekamy na callback (max 5 min).
      final code = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () =>
            throw TimeoutException('Logowanie przekroczyło limit czasu.'),
      );

      // Wymieniamy kod na sesję (SDK używa zapisanego PKCE verifier).
      await _client.auth.exchangeCodeForSession(code);
    } finally {
      await server?.close(force: true);
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
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
