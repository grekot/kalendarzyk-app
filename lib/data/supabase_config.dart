/// Konfiguracja Supabase.
///
/// Po utworzeniu projektu na supabase.com:
///   Project Settings → API → skopiuj URL i anon public key
/// i wklej poniżej.
///
/// Plik jest commitowany — anon key jest *publiczny* (chroniony przez Row-Level
/// Security w bazie). Service role key NIGDY nie powinien się tu znaleźć.
class SupabaseConfig {
  static const String url = 'https://tkvxeozttwxxfpvmvvwp.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRrdnhlb3p0dHd4eGZwdm12dndwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwODkxNzQsImV4cCI6MjA5NDY2NTE3NH0._fcfp0YXEqb1rE5aEQ4Ci_ojOINqUUVHqabPTUE0GjQ';

  static bool get isConfigured =>
      !url.startsWith('TODO_') && !anonKey.startsWith('TODO_');
}
