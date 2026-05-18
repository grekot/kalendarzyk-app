# Jak zbudować APK — instrukcja

## Stan obecny

Projekt jest **w pełni gotowy do buildu**. Wzorowany na `slowenia_app` — ten sam toolchain (JDK 17, Flutter 3.41.9 stable, Android SDK 36), ten sam stack (Riverpod + Hive + Material 3 + locale pl_PL).

`flutter pub get` wykonane przy generowaniu projektu.

## Build APK

Otwórz **zwykły PowerShell** (Win+R → `powershell`, nie przez Claude) i wykonaj:

```powershell
cd "C:\TMP\Android\Kalendarzyk"
flutter build apk --release --split-per-abi
```

Pierwszy build potrwa **5–15 minut** (Gradle, NDK, AOT). Drugi i kolejne: ~30-60s.

Po sukcesie zobaczysz w `build\app\outputs\flutter-apk\` trzy pliki:
- `app-armeabi-v7a-release.apk` — 32-bit ARM
- `app-arm64-v8a-release.apk` — **64-bit ARM (Twój telefon — ten ściągasz)**
- `app-x86_64-release.apk` — x86 (emulator)

## Wgranie na telefon

1. Skopiuj `app-arm64-v8a-release.apk` (~20 MB) na telefon — kabel USB, Google Drive, email, cokolwiek.
2. Na telefonie: Ustawienia → Bezpieczeństwo → włącz „Nieznane źródła" dla aplikacji której użyjesz do otwarcia APK.
3. Tap APK → Zainstaluj.
4. Aplikacja startuje pusta — kliknij „Dodaj początek menstruacji" żeby dodać pierwszy wpis.

## Jeśli build padnie

### Błędy „Type X not found"

Stary `.dart_tool` cache. Wykonaj:

```powershell
cd "C:\TMP\Android\Kalendarzyk"
flutter clean
flutter pub get
flutter build apk --release --split-per-abi
```

### Błąd „java.io.IOException: Unable to establish loopback connection"

Występuje w harnessie Claude (Gradle daemon spawn). W normalnym terminalu nie powinien się pojawić. Jeśli mimo to — sprawdź czy nie blokuje go AV lub Defender Application Control.

### Inne

Sprawdź `flutter doctor`. Wszystko powinno być zielone.

## Iteracja w przyszłości

### Backup danych

W apce: menu (ikona w lewym górnym rogu) → „Eksportuj dane" → udostępnij plik JSON. Trzymaj kopię.

### Migracja danych po reinstalacji

Po instalacji nowej wersji APK: menu → „Importuj z pliku" → wybierz wcześniej zapisany backup → „Scal".

### Zmiany w kodzie

```powershell
cd "C:\TMP\Android\Kalendarzyk"
# edytuj pliki w lib\...
flutter build apk --release --split-per-abi
# wgraj nowy APK na telefon
```

## Struktura projektu

```
Kalendarzyk/
├── pubspec.yaml                        # dependencies
├── android/                            # build config
└── lib/
    ├── main.dart                       # bootstrap (Hive init, locale pl_PL)
    ├── theme.dart                      # Material 3, seedColor #C2185B
    ├── data/
    │   ├── cycle_repository.dart       # CRUD na Hive, eksport/import JSON
    │   └── cycle_stats.dart            # lastStart, średnia, prognoza
    ├── providers/
    │   └── providers.dart              # CyclesNotifier (Riverpod)
    ├── widgets/
    │   ├── info_card.dart              # karta z tytułem + treścią
    │   ├── add_cycle_start_dialog.dart # dialog „dziś / podaj datę"
    │   └── cycle_day_sheet.dart        # bottom sheet edytuj/usuń
    └── screens/
        ├── home_screen.dart            # karty info + przyciski + drawer
        └── calendar_screen.dart        # TableCalendar z markerami
```

## Co aplikacja umie

- Dodaj start cyklu (dziś / wybór daty z kalendarza).
- Pokazuje datę ostatniego cyklu i ile dni temu.
- Prognozuje datę kolejnego cyklu na podstawie średniej z ostatnich 6 cykli (lub mniej, jeśli mniej wpisów).
- Kalendarz miesięczny/tygodniowy z zaznaczonymi startami (czerwone kółka) i przewidywaną datą (żółta obwódka).
- Edycja/usunięcie wpisu przez tap w zaznaczony dzień w kalendarzu.
- Eksport/import danych do JSON-a (przez systemowe share-sheet i file-picker).
- Reset wszystkich danych.
- Działanie w pełni offline. Dane lokalne (Hive).

## Konfiguracja toolchainu

Patrz `slowenia_app/JAK_ZBUDOWAC.md` — ten sam zestaw zmiennych środowiskowych (JAVA_HOME, ANDROID_HOME, Flutter SDK).
