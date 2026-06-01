# Changelog

Wszystkie istotne zmiany w tym projekcie zapisujemy tutaj.

Format wzorowany na [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/),
wersjonowanie zgodne z [Semantic Versioning](https://semver.org/lang/pl/):
- **MAJOR** — zmiany niekompatybilne (np. wymagany reset danych użytkowników).
- **MINOR** — nowe funkcjonalności, kompatybilne wstecz.
- **PATCH** — bugfixy, drobne poprawki.

`+BUILD` to monotonicznie rosnący numer Android `versionCode` — bumpuje się
przy **każdym** wgranym APK żeby Android rozpoznał aktualizację (niezależnie
od MAJOR/MINOR/PATCH).

## [Unreleased]

_Pusto — wszystko z bieżącej iteracji zostało wydane jako 1.1.0+2._

## [1.1.0+2] - 2026-06-01

### Dodane
- **Auto-update z GitHub Releases** — apka przy każdym uruchomieniu sprawdza najnowszy release w repo, pokazuje SnackBar „Dostępna nowa wersja X.Y.Z" z akcją „Aktualizuj". Tap → dialog z release notes + przycisk „Pobierz i zainstaluj" → APK pobiera się do tmp i otwiera systemowy instalator Androida.
- **GitHub Action `release.yml`** — push tagu `v*` automatycznie buduje APK, podpisuje release keystorem (z GitHub Secrets), tworzy Release z notatkami z `CHANGELOG.md` i wgrywa APK jako asset.
- **Release keystore signing** — `android/app/build.gradle.kts` wspiera lokalny `key.properties` (dla `flutter build apk --release` z laptopa) oraz env vars w CI. Fallback do debug keystore gdy ani jedno ani drugie nie jest skonfigurowane.
- **Google Sign-In** zastępuje anonymous auth Supabase (recovery przez konto Google, professional UX).
- **Role w udostępnianiu profili**: editor (pełen dostęp do cykli) / viewer (tylko podgląd). Owner wybiera rolę przy generowaniu kodu, może ją zmienić później przez popup menu.
- **Dni płodne i okno owulacji** — nowa karta na home, markery w kalendarzu (zielone obramowanie dla okna płodnego, pełne ciemnozielone kółko dla owulacji). Włącznie z disclaimerem.
- **Konfigurowalny margines błędu owulacji** (±0 do ±3 dni, default ±1) — per profil, edytuje owner przez ikonę „tune" w ekranie zarządzania profilami.
- **Toggle wyświetlania prognozy** dni płodnych w kalendarzu (per urządzenie, zapamiętany w `SharedPreferences`).
- **Propozycja zapisania kopii** (dialog Tak/Nie) po dodaniu nowego wpisu cyklu.
- **GitHub Actions keep-alive** — codzienny ping Supabase żeby projekt nie zapauzował się na free tier po 7 dniach nieaktywności.
- **Ikona aplikacji** — kalendarz z numerem „28" w kolorach motywu.
- **Wyświetlanie wersji apki** w drawerze (sekcja „O aplikacji").
- **localhost OAuth** dla Windows desktop — sign-in działa też na PC bez deep linków.

### Zmienione
- **Nazwa wyświetlana**: `Kalendazyk` → `Kalendarzyk` (typo fix; technical identifier `kalendazyk` w pubspec / applicationId pozostaje, żeby Android rozpoznał update zamiast instalować jako osobna apka).
- **Dzień bieżący w kalendarzu** → jasnoniebieski (Material Blue 200), żeby odróżnić od startu cyklu (czerwone).
- **Okno płodne** rozszerzone z 7 do 9-13 dni (zależne od `ovulationUncertainty`) — uwzględnia niepewność prognozy owulacji z obu stron.
- **Release APK podpisywany dedykowanym keystore'em** (zamiast `debug.keystore`). **Migracja jednorazowa** — pierwszy APK z tej wersji trzeba zainstalować ręcznie **po odinstalowaniu starej apki** (Android odmawia update przy zmianie signature). Od kolejnej wersji auto-update śmiga sam.

### Naprawione
- RLS `infinite recursion detected` (42P17) — wprowadzone `SECURITY DEFINER` helper functions (`is_profile_owner`, `has_profile_share`, `user_can_access_profile`) żeby policies nie zapętlały się.
- RLS `new row violates row-level security policy for table "users"` (42501) — dorzucone `users_insert_self` + backfill istniejących anonymous userów.
- Brak permission `INTERNET` w release manifest Androida — `SocketException: Failed host lookup` przy próbie logowania.
- HomeScreen po imporcie pierwszego profilu pokazywał „brak profili" — fix stale-flag w `_maybeInitActiveProfile`.

### Migracje SQL
- `002_share_roles.sql` — kolumna `role text` w `profile_shares` i `invites` (`editor` / `viewer`).
- `003_ovulation_uncertainty.sql` — kolumna `ovulation_uncertainty smallint (0..3)` w `profiles`.
- `004_uncertainty_default_one.sql` — zmiana defaultu z 2 na 1 (plus update istniejących wierszy).

## [1.0.0+1] - 2026-05-18

### Pierwsze wydanie
- Tracker cyklu menstruacyjnego dla Androida i Windows desktop.
- Dodawanie startów cyklu (dziś / wybór daty).
- Kalendarz z markerami startów i przewidywanej kolejnej miesiączki.
- Prognoza kolejnego cyklu na podstawie średniej z ostatnich 6 cykli.
- Wiele profili per user, udostępnianie 6-cyfrowym kodem parowania (TTL 10 min).
- Zdjęcia profili w Supabase Storage z fallbackiem do inicjału.
- Eksport/import JSON (per profil, format v2).
- Anonymous Supabase Auth + Row-Level Security.

Stack: Flutter 3.41 + Riverpod 2 + Supabase + Material 3 + locale pl_PL.
