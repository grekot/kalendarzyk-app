import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/person.dart';
import '../providers/providers.dart';
import '../widgets/person_avatar.dart';
import 'profile_share_screen.dart';

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personsAsync = ref.watch(personsProvider);
    final activeId = ref.watch(activePersonIdProvider);
    final defaultIdAsync = ref.watch(defaultProfileIdProvider);
    final currentUserId = ref.watch(currentUserIdProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Dodaj profil'),
        onPressed: () => _addPerson(context, ref),
      ),
      body: SafeArea(
        child: personsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Błąd: $e')),
          data: (persons) {
            final defaultId = defaultIdAsync.valueOrNull;
            if (persons.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Brak profili. Dodaj pierwszy przyciskiem poniżej.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              itemCount: persons.length,
              itemBuilder: (_, i) {
                final p = persons[i];
                final mine = p.isOwnedBy(currentUserId);
                final isDefault = p.id == defaultId;
                final theme = Theme.of(context);
                final canDelete = mine && persons.length > 1;

                return ListTile(
                  leading: GestureDetector(
                    onTap: mine ? () => _changePhoto(context, ref, p) : null,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        PersonAvatar(person: p, size: 40),
                        if (mine)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                  width: 1,
                                ),
                              ),
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.photo_camera,
                                size: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (isDefault)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.star,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  subtitle: mine
                      ? (isDefault ? const Text('Domyślna') : null)
                      : Text(
                          'udostępnione przez ${p.ownerName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: PopupMenuButton<_ProfileAction>(
                    tooltip: 'Akcje',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) => _handleAction(
                      context,
                      ref,
                      action,
                      p,
                      activeId,
                    ),
                    itemBuilder: (_) {
                      final items = <PopupMenuEntry<_ProfileAction>>[];
                      if (!isDefault) {
                        items.add(_menuItem(
                          _ProfileAction.setDefault,
                          Icons.star_border,
                          'Ustaw jako domyślną',
                        ));
                      }
                      if (mine) {
                        items.add(_menuItem(
                          _ProfileAction.share,
                          Icons.share_outlined,
                          'Udostępnij',
                        ));
                        items.add(_menuItem(
                          _ProfileAction.rename,
                          Icons.edit_outlined,
                          'Zmień nazwę',
                        ));
                        items.add(_menuItem(
                          _ProfileAction.tune,
                          Icons.tune,
                          'Margines owulacji (±${p.ovulationUncertainty})',
                        ));
                        if (canDelete) {
                          items.add(const PopupMenuDivider());
                          items.add(PopupMenuItem(
                            value: _ProfileAction.delete,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Usuń profil',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ));
                        }
                      } else {
                        items.add(_menuItem(
                          _ProfileAction.leave,
                          Icons.exit_to_app,
                          'Opuść udostępniony profil',
                        ));
                      }
                      return items;
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _ProfileAction action,
    Person person,
    String? activeId,
  ) async {
    switch (action) {
      case _ProfileAction.setDefault:
        await ref.read(authServiceProvider).setDefaultProfileId(person.id);
        ref.invalidate(defaultProfileIdProvider);
      case _ProfileAction.share:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfileShareScreen(profile: person),
          ),
        );
      case _ProfileAction.rename:
        await _renamePerson(context, ref, person);
      case _ProfileAction.tune:
        await _changeUncertainty(context, ref, person);
      case _ProfileAction.delete:
        await _deletePerson(context, ref, person, activeId);
      case _ProfileAction.leave:
        await _leaveShared(context, ref, person, activeId);
    }
  }

  Future<void> _addPerson(BuildContext context, WidgetRef ref) async {
    final name = await _promptName(context, title: 'Dodaj profil');
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(personRepositoryProvider).create(name: name);
    } catch (e) {
      if (context.mounted) _showError(context, 'Nie udało się dodać: $e');
    }
  }

  Future<void> _renamePerson(
      BuildContext context, WidgetRef ref, Person person) async {
    final name = await _promptName(
      context,
      title: 'Zmień nazwę',
      initial: person.name,
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(personRepositoryProvider).rename(person.id, name);
    } catch (e) {
      if (context.mounted) _showError(context, 'Nie udało się: $e');
    }
  }

  Future<void> _changeUncertainty(
      BuildContext context, WidgetRef ref, Person person) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        var selected = person.ovulationUncertainty;
        return StatefulBuilder(
          builder: (sbContext, setState) {
            return AlertDialog(
              title: const Text('Margines błędu owulacji'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Określa o ile dni rzeczywista owulacja może odbiegać '
                    'od średniej statystycznej. Dla cykli regularnych — niżej; '
                    'dla nieregularnych — wyżej. Szersze okno = bardziej '
                    'konserwatywne dni płodne.',
                    style: Theme.of(sbContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('±0')),
                        ButtonSegment(value: 1, label: Text('±1')),
                        ButtonSegment(value: 2, label: Text('±2')),
                        ButtonSegment(value: 3, label: Text('±3')),
                      ],
                      selected: {selected},
                      onSelectionChanged: (s) =>
                          setState(() => selected = s.first),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selected == 0
                        ? 'Owulacja: pojedynczy przewidywany dzień.'
                        : 'Owulacja: zakres $selected ${selected == 1 ? "dnia" : "dni"} w obie strony '
                            '(${1 + selected * 2} dni razem).',
                    style: Theme.of(sbContext).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Anuluj'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(selected),
                  child: const Text('Zapisz'),
                ),
              ],
            );
          },
        );
      },
    );
    if (picked == null || picked == person.ovulationUncertainty) return;
    try {
      await ref
          .read(personRepositoryProvider)
          .setOvulationUncertainty(person.id, picked);
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Nie udało się zapisać: $e');
      }
    }
  }

  Future<void> _deletePerson(
    BuildContext context,
    WidgetRef ref,
    Person person,
    String? activeId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć profil?'),
        content: Text(
          'Profil „${person.name}" wraz z cyklami i zdjęciem zostanie '
          'trwale usunięty u wszystkich osób z dostępem. Czy kontynuować?',
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
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(storageServiceProvider)
          .deleteAllForProfile(person.id);
      await ref.read(personRepositoryProvider).delete(person.id);
      if (activeId == person.id) {
        ref.read(activePersonIdProvider.notifier).state = null;
      }
    } catch (e) {
      if (context.mounted) _showError(context, 'Nie udało się usunąć: $e');
    }
  }

  Future<void> _leaveShared(
    BuildContext context,
    WidgetRef ref,
    Person person,
    String? activeId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Opuścić udostępniony profil?'),
        content: Text(
          'Stracisz dostęp do profilu „${person.name}". Właściciel '
          '(${person.ownerName}) może udostępnić go ponownie kodem.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Opuść'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(personRepositoryProvider).leaveShared(person.id);
      if (activeId == person.id) {
        ref.read(activePersonIdProvider.notifier).state = null;
      }
    } catch (e) {
      if (context.mounted) _showError(context, 'Nie udało się: $e');
    }
  }

  Future<void> _changePhoto(
      BuildContext context, WidgetRef ref, Person person) async {
    final hasPhoto = person.photoUrl != null;
    final action = await showDialog<_PhotoAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zdjęcie profilu'),
        content: Text(hasPhoto
            ? 'Możesz wybrać nowe zdjęcie lub usunąć obecne. Zmiana jest '
                'widoczna dla wszystkich z dostępem do tego profilu.'
            : 'Wybierz zdjęcie z dysku. Zostanie wgrane do chmury i widoczne '
                'dla wszystkich z dostępem do tego profilu.'),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Anuluj'),
          ),
          if (hasPhoto)
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_PhotoAction.remove),
              child: const Text('Usuń zdjęcie'),
            ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_PhotoAction.pick),
            icon: const Icon(Icons.image),
            label: const Text('Wybierz z dysku'),
          ),
        ],
      ),
    );
    if (action == null) return;

    final personRepo = ref.read(personRepositoryProvider);
    final storage = ref.read(storageServiceProvider);

    if (action == _PhotoAction.remove) {
      final old = person.photoUrl;
      try {
        await personRepo.updatePhotoUrl(person.id, null);
        if (old != null) await storage.deleteByUrl(old);
      } catch (e) {
        if (context.mounted) _showError(context, 'Nie udało się: $e');
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Wybierz zdjęcie profilu',
    );
    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    try {
      final url = await storage.uploadProfilePhoto(
        profileId: person.id,
        source: File(sourcePath),
      );
      final old = person.photoUrl;
      await personRepo.updatePhotoUrl(person.id, url);
      if (old != null && old != url) {
        await storage.deleteByUrl(old);
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Nie udało się wgrać zdjęcia: $e');
      }
    }
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: 'Imię / nazwa profilu',
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    return result;
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _PhotoAction { pick, remove }

enum _ProfileAction { setDefault, share, rename, tune, delete, leave }

PopupMenuItem<_ProfileAction> _menuItem(
  _ProfileAction value,
  IconData icon,
  String label,
) {
  return PopupMenuItem<_ProfileAction>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
