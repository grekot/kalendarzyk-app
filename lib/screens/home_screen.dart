import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/cycle_repository.dart';
import '../data/cycle_stats.dart';
import '../models/person.dart';
import '../providers/providers.dart';
import '../theme.dart';
import '../widgets/add_cycle_start_dialog.dart';
import '../widgets/import_dialog.dart';
import '../widgets/info_card.dart';
import '../widgets/join_profile_dialog.dart';
import '../widgets/person_avatar.dart';
import 'calendar_screen.dart';
import 'profiles_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _activeInitialized = false;

  @override
  Widget build(BuildContext context) {
    _maybeInitActiveProfile();

    final activePerson = ref.watch(activePersonProvider);
    final cyclesAsync = ref.watch(cyclesProvider);
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
                ),
              ),
      ),
    );
  }

  void _maybeInitActiveProfile() {
    if (_activeInitialized) return;
    final personsAsync = ref.watch(personsProvider);
    final defaultAsync = ref.watch(defaultProfileIdProvider);
    if (!personsAsync.hasValue || !defaultAsync.hasValue) return;
    final persons = personsAsync.value!;
    final defaultId = defaultAsync.value;
    if (persons.isEmpty) {
      _activeInitialized = true;
      return;
    }
    final pick = (defaultId != null &&
            persons.any((p) => p.id == defaultId))
        ? defaultId
        : persons.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activePersonIdProvider.notifier).state = pick;
      setState(() => _activeInitialized = true);
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

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.starts,
    required this.today,
    required this.fmt,
  });

  final List<DateTime> starts;
  final DateTime today;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final last = CycleStats.lastStart(starts);
    final avg = CycleStats.averageLengthDays(starts);
    final lengths = CycleStats.cycleLengths(starts);
    final predicted = CycleStats.predictedNextStart(starts);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
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
            onPressed: () => AddCycleStartDialog.show(context),
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
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('O aplikacji'),
              subtitle: Text('Tracker cyklu menstruacyjnego'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final persons = ref.read(personsProvider).valueOrNull ?? [];
      if (persons.isEmpty) return;
      final activeId = ref.read(activePersonIdProvider);
      final chosen = await _pickPersonForExport(context, persons, activeId);
      if (chosen == null) return;

      final repo = ref.read(cycleRepositoryProvider);
      final jsonStr = await repo.exportJson(chosen.id, personName: chosen.name);
      final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final safeName = chosen.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final fileName =
          'kalendazyk_${safeName.isEmpty ? "profil" : safeName}_$stamp.json';

      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(jsonStr);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/json')],
          subject: 'Kalendarzyk — kopia zapasowa (${chosen.name})',
        );
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Zapisz kopię zapasową — ${chosen.name}',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
        if (path == null) return;
        await File(path).writeAsString(jsonStr);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Zapisano: $path')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd eksportu: $e')),
        );
      }
    }
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
