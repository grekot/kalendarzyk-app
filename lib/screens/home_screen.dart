import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/cycle_repository.dart';
import '../data/cycle_stats.dart';
import '../data/update_checker.dart';
import '../models/person.dart';
import '../providers/providers.dart';
import '../theme.dart';
import '../widgets/add_cycle_start_dialog.dart';
import '../widgets/backup_prompt.dart';
import '../widgets/import_dialog.dart';
import '../widgets/info_card.dart';
import '../widgets/join_profile_dialog.dart';
import '../widgets/person_avatar.dart';
import '../widgets/update_dialog.dart';
import 'calendar_screen.dart';
import 'profiles_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    final info = await UpdateChecker().checkForUpdate();
    if (info == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('Dostępna nowa wersja ${info.tag}'),
        action: SnackBarAction(
          label: 'Aktualizuj',
          onPressed: () {
            if (mounted) {
              UpdateDialog.show(
                context,
                info: info,
                checker: UpdateChecker(),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _maybeInitActiveProfile();

    final activePerson = ref.watch(activePersonProvider);
    final cyclesAsync = ref.watch(cyclesProvider);
    final myId = ref.watch(currentUserIdProvider).valueOrNull;
    final canEdit = activePerson?.canEdit(myId) ?? false;
    final today = dateOnly(DateTime.now());
    final fmtLong = DateFormat('d MMMM yyyy', 'pl_PL');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          activePerson == null ? 'Kalendarzyk' : 'Kalendarzyk — ${activePerson.name}',
        ),
        actions: [
          if (activePerson != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _PersonSwitcherButton(activePerson: activePerson),
            ),
        ],
      ),
      drawer: const _HomeDrawer(),
      body: SafeArea(
        child: activePerson == null
            ? const _NoProfilesView()
            : cyclesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Nie udało się wczytać cykli:\n$e',
                        textAlign: TextAlign.center),
                  ),
                ),
                data: (starts) => _HomeBody(
                  starts: starts,
                  today: today,
                  fmt: fmtLong,
                  canEdit: canEdit,
                ),
              ),
      ),
    );
  }

  void _maybeInitActiveProfile() {
    // Jeśli aktywny profil jest już ustawiony — nic nie robimy.
    if (ref.read(activePersonIdProvider) != null) return;

    final personsAsync = ref.watch(personsProvider);
    final defaultAsync = ref.watch(defaultProfileIdProvider);
    if (!personsAsync.hasValue || !defaultAsync.hasValue) return;
    final persons = personsAsync.value!;
    // Brak profili — czekamy aż user doda / zaimportuje pierwszy.
    if (persons.isEmpty) return;

    final defaultId = defaultAsync.value;
    final pick = (defaultId != null && persons.any((p) => p.id == defaultId))
        ? defaultId
        : persons.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activePersonIdProvider.notifier).state = pick;
    });
  }
}

class _NoProfilesView extends StatelessWidget {
  const _NoProfilesView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nie masz jeszcze żadnego profilu. Otwórz boczne menu '
              'i wybierz „Zarządzaj profilami" żeby dodać pierwszy, '
              'lub „Dołącz przez kod" żeby dołączyć do udostępnionego.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Builder(builder: (ctx) {
              return FilledButton.icon(
                icon: const Icon(Icons.menu),
                label: const Text('Otwórz menu'),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({
    required this.starts,
    required this.today,
    required this.fmt,
    required this.canEdit,
  });

  final List<DateTime> starts;
  final DateTime today;
  final DateFormat fmt;
  final bool canEdit;

  Future<void> _onAddPressed(BuildContext context, WidgetRef ref) async {
    final addedDate = await AddCycleStartDialog.show(context);
    if (addedDate == null || !context.mounted) return;
    final activePerson = ref.read(activePersonProvider);
    if (activePerson == null) return;
    final shouldBackup = await BackupPrompt.askAfterCycleAdded(
      context,
      person: activePerson,
      addedDate: addedDate,
    );
    if (shouldBackup && context.mounted) {
      await BackupPrompt.exportProfile(context, ref, activePerson);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = CycleStats.lastStart(starts);
    final avg = CycleStats.averageLengthDays(starts);
    final lengths = CycleStats.cycleLengths(starts);
    final predicted = CycleStats.predictedNextStart(starts);
    final showFertility = ref.watch(showFertilityProvider);
    final activePerson = ref.watch(activePersonProvider);
    final uncert = activePerson?.ovulationUncertainty ??
        Person.defaultOvulationUncertainty;
    final fertileWindow = showFertility
        ? CycleStats.predictedFertileWindow(
            starts,
            ovulationUncertainty: uncert,
          )
        : null;
    final ovulationDay =
        showFertility ? CycleStats.predictedOvulationDay(starts) : null;
    final ovulationWindow = showFertility
        ? CycleStats.predictedOvulationWindow(
            starts,
            ovulationUncertainty: uncert,
          )
        : null;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (!canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.visibility,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tylko podgląd — właściciel nie dał Ci prawa edycji cykli.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        InfoCard(
          title: 'Ostatni cykl',
          icon: Icons.water_drop,
          iconColor: CycleColors.period,
          child: last == null
              ? const Text('Brak danych — dodaj pierwszy wpis.')
              : _LastCycleBody(date: last, today: today, fmt: fmt),
        ),
        InfoCard(
          title: 'Przewidywany kolejny cykl',
          icon: Icons.event,
          iconColor: CycleColors.predicted,
          child: predicted == null
              ? const Text('Potrzeba min. 2 wpisów żeby policzyć średnią.')
              : _PredictedBody(
                  date: predicted,
                  today: today,
                  avg: avg!,
                  sampleSize: lengths.length,
                  fmt: fmt,
                ),
        ),
        if (showFertility)
          InfoCard(
            title: 'Okno płodne',
            icon: Icons.local_florist,
            iconColor: CycleColors.ovulation,
            child: fertileWindow == null
                ? const Text('Potrzeba min. 2 wpisów żeby policzyć okno.')
                : _FertileWindowBody(
                    start: fertileWindow.start,
                    end: fertileWindow.end,
                    ovulation: ovulationDay!,
                    ovulationStart: ovulationWindow!.start,
                    ovulationEnd: ovulationWindow.end,
                    uncertainty: uncert,
                    today: today,
                    fmt: fmt,
                  ),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            icon: const Icon(Icons.water_drop),
            label: const Text('Dodaj początek menstruacji'),
            onPressed: canEdit ? () => _onAddPressed(context, ref) : null,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.calendar_month),
            label: const Text('Kalendarz cykli'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CalendarScreen()),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LastCycleBody extends StatelessWidget {
  const _LastCycleBody({required this.date, required this.today, required this.fmt});
  final DateTime date;
  final DateTime today;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final daysAgo = today.difference(date).inDays;
    final ago = daysAgo == 0
        ? 'dziś'
        : daysAgo == 1
            ? 'wczoraj'
            : '$daysAgo dni temu';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fmt.format(date), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(ago, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _PredictedBody extends StatelessWidget {
  const _PredictedBody({
    required this.date,
    required this.today,
    required this.avg,
    required this.sampleSize,
    required this.fmt,
  });

  final DateTime date;
  final DateTime today;
  final int avg;
  final int sampleSize;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final diff = date.difference(today).inDays;
    String when;
    if (diff == 0) {
      when = 'dziś';
    } else if (diff > 0) {
      when = diff == 1 ? 'za 1 dzień' : 'za $diff dni';
    } else {
      final overdue = -diff;
      when = overdue == 1 ? 'spóźnione o 1 dzień' : 'spóźnione o $overdue dni';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fmt.format(date), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(when, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(
          'Średnia: $avg dni (z $sampleSize ${_pluralCycles(sampleSize)})',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _pluralCycles(int n) {
    if (n == 1) return 'cyklu';
    return 'cykli';
  }
}

class _FertileWindowBody extends StatelessWidget {
  const _FertileWindowBody({
    required this.start,
    required this.end,
    required this.ovulation,
    required this.ovulationStart,
    required this.ovulationEnd,
    required this.uncertainty,
    required this.today,
    required this.fmt,
  });

  final DateTime start;
  final DateTime end;
  final DateTime ovulation;
  final DateTime ovulationStart;
  final DateTime ovulationEnd;
  final int uncertainty;
  final DateTime today;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmtShort = DateFormat('d MMM', 'pl_PL');
    final inWindow = !today.isBefore(_dateOnly(start)) &&
        !today.isAfter(_dateOnly(end));
    final isPast = today.isAfter(_dateOnly(end));
    final daysToOvulation = _dateOnly(ovulation).difference(today).inDays;

    String status;
    if (isPast) {
      status = 'Minęło — następne po kolejnej miesiączce.';
    } else if (inWindow) {
      if (daysToOvulation == 0) {
        status = 'Trwa — dziś szczyt owulacji.';
      } else if (daysToOvulation > 0) {
        status = daysToOvulation == 1
            ? 'Trwa — owulacja jutro.'
            : 'Trwa — owulacja za $daysToOvulation dni.';
      } else {
        status = 'Trwa — po owulacji.';
      }
    } else {
      final daysToStart = _dateOnly(start).difference(today).inDays;
      status = daysToStart == 1
          ? 'Zacznie się jutro.'
          : 'Zacznie się za $daysToStart dni.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${fmtShort.format(start)} – ${fmt.format(end)}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(status, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(
          uncertainty == 0
              ? 'Owulacja: ${fmtShort.format(ovulation)}'
              : 'Owulacja: ${fmtShort.format(ovulationStart)} – '
                  '${fmtShort.format(ovulationEnd)} (szczyt ${fmtShort.format(ovulation)}, ±$uncertainty ${uncertainty == 1 ? "dzień" : "dni"})',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Przewidywania orientacyjne. Nie zastępują metod planowania rodziny.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

// ────────────────────────────────────────────────────────────────
// Drawer
// ────────────────────────────────────────────────────────────────

class _HomeDrawer extends ConsumerWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayNameAsync = ref.watch(displayNameProvider);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/icon/calendar_icon.png',
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Kalendarzyk',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayNameAsync.maybeWhen(
                              data: (n) =>
                                  n.isEmpty ? '' : 'Zalogowany jako: $n',
                              orElse: () => '',
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('Zarządzaj profilami'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfilesScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('Dołącz przez kod'),
              subtitle: const Text('Wpisz 6-cyfrowy kod udostępnienia'),
              onTap: () async {
                final id = await JoinProfileDialog.show(context);
                if (id != null) {
                  ref.read(activePersonIdProvider.notifier).state = id;
                  if (context.mounted) {
                    Navigator.of(context).maybePop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Dołączono do profilu.')),
                    );
                  }
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Eksportuj dane'),
              subtitle: const Text('Zapisz kopię JSON dla wybranej osoby'),
              onTap: () async {
                await _exportData(context, ref);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Importuj z pliku'),
              subtitle: const Text('Wczytaj kopię JSON'),
              onTap: () async {
                await _importData(context, ref);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_forever,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Wyczyść cykle aktywnej osoby'),
              onTap: () async {
                await _resetData(context, ref);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Wyloguj'),
              subtitle: const Text('Zakończ sesję Google'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Wylogować?'),
                    content: const Text(
                      'Stracisz dostęp do danych w chmurze do czasu '
                      'ponownego zalogowania tym samym kontem Google.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Anuluj'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Wyloguj'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(authServiceProvider).signOut();
                  // AuthGate sam przerenderuje na SignInScreen.
                }
              },
            ),
            const Divider(),
            const _AboutTile(),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final persons = ref.read(personsProvider).valueOrNull ?? [];
    if (persons.isEmpty) return;
    final activeId = ref.read(activePersonIdProvider);
    final chosen = await _pickPersonForExport(context, persons, activeId);
    if (chosen == null || !context.mounted) return;
    await BackupPrompt.exportProfile(context, ref, chosen);
  }

  Future<Person?> _pickPersonForExport(
    BuildContext context,
    List<Person> persons,
    String? activeId,
  ) async {
    if (persons.length == 1) return persons.single;
    return showModalBottomSheet<Person>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Eksportuj dane której osoby?',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final p in persons)
              ListTile(
                leading: PersonAvatar(person: p),
                title: Text(p.name),
                subtitle: p.id == activeId ? const Text('Aktywna') : null,
                onTap: () => Navigator.of(sheetContext).pop(p),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final jsonStr = await File(path).readAsString();
      final cycleRepo = ref.read(cycleRepositoryProvider);
      final parsed = cycleRepo.parseImport(jsonStr);

      if (!context.mounted) return;
      final persons = ref.read(personsProvider).valueOrNull ?? [];
      final myId = ref.read(currentUserIdProvider).valueOrNull;
      final myPersons = persons.where((p) => p.isOwnedBy(myId)).toList();

      final target = await ImportDialog.show(
        context,
        persons: myPersons,
        activePersonId: ref.read(activePersonIdProvider),
        sourceName: parsed.personName,
        incomingCount: parsed.starts.length,
      );
      if (target == null) return;

      String targetId;
      String targetName;
      if (target.isNew) {
        final created = await ref
            .read(personRepositoryProvider)
            .create(name: target.newProfileName!);
        targetId = created.id;
        targetName = created.name;
      } else {
        final p = myPersons.firstWhere((p) => p.id == target.existingProfileId);
        targetId = p.id;
        targetName = p.name;
      }

      await cycleRepo.importJson(
        targetId,
        jsonStr,
        replace: target.mode == ImportMode.replace,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zaimportowano do „$targetName".')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd importu: $e')),
        );
      }
    }
  }

  Future<void> _resetData(BuildContext context, WidgetRef ref) async {
    final active = ref.read(activePersonProvider);
    if (active == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wyczyścić cykle?'),
        content: Text(
          'Wszystkie wpisy cykli dla profilu „${active.name}" zostaną '
          'usunięte u wszystkich osób z dostępem. Sam profil pozostanie. '
          'Operacji nie można cofnąć.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Wyczyść'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(cycleRepositoryProvider).clear(active.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cykle wyczyszczone.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd: $e')),
        );
      }
    }
  }
}

// ────────────────────────────────────────────────────────────────
// PopupMenu przełącznika profilu
// ────────────────────────────────────────────────────────────────

class _PersonSwitcherButton extends ConsumerWidget {
  const _PersonSwitcherButton({required this.activePerson});

  final Person activePerson;

  static const String _manageKey = '__manage__';
  static const String _joinKey = '__join__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Przełącz osobę',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      icon: PersonAvatar(person: activePerson, size: 32),
      onSelected: (value) async {
        if (value == _manageKey) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfilesScreen()),
          );
        } else if (value == _joinKey) {
          final id = await JoinProfileDialog.show(context);
          if (id != null) {
            ref.read(activePersonIdProvider.notifier).state = id;
          }
        } else {
          ref.read(activePersonIdProvider.notifier).state = value;
        }
      },
      itemBuilder: (context) {
        final persons = ref.read(personsProvider).valueOrNull ?? [];
        final activeId = ref.read(activePersonIdProvider);
        final myId = ref.read(currentUserIdProvider).valueOrNull;
        return [
          for (final p in persons)
            PopupMenuItem<String>(
              value: p.id,
              child: Row(
                children: [
                  PersonAvatar(person: p, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.name),
                        if (!p.isOwnedBy(myId))
                          Text(
                            'od ${p.ownerName}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (p.id == activeId) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: _joinKey,
            child: Row(
              children: [
                Icon(Icons.group_add, size: 24),
                SizedBox(width: 10),
                Text('Dołącz przez kod…'),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: _manageKey,
            child: Row(
              children: [
                Icon(Icons.manage_accounts, size: 24),
                SizedBox(width: 10),
                Text('Zarządzaj profilami…'),
              ],
            ),
          ),
        ];
      },
    );
  }
}

/// ListTile pokazujący wersję apki — dynamicznie pobiera z pubspec
/// przez package_info_plus.
class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final version = snap.data == null
            ? '…'
            : '${snap.data!.version} (build ${snap.data!.buildNumber})';
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('O aplikacji'),
          subtitle: Text('Kalendarzyk $version'),
        );
      },
    );
  }
}
