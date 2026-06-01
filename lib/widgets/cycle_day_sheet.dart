import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';

class CycleDaySheet extends ConsumerWidget {
  const CycleDaySheet({super.key, required this.date});

  final DateTime date;

  static Future<void> show(BuildContext context, DateTime date) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => CycleDaySheet(date: date),
    );
  }

  String? _activeProfileId(WidgetRef ref) => ref.read(activePersonIdProvider);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('EEEE, d MMMM yyyy', 'pl_PL');
    final activePerson = ref.watch(activePersonProvider);
    final myId = ref.watch(currentUserIdProvider).valueOrNull;
    final canEdit = activePerson?.canEdit(myId) ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              fmt.format(date),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              canEdit
                  ? 'Zaznaczony start cyklu'
                  : 'Zaznaczony start cyklu (tylko podgląd)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!canEdit)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Zamknij'),
                ),
              ),
            if (canEdit) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.edit_calendar),
                label: const Text('Zmień datę'),
                onPressed: () async {
                final picked = await _pickDate(context, date);
                if (picked == null) return;
                final id = _activeProfileId(ref);
                if (id == null) return;
                try {
                  await ref
                      .read(cycleRepositoryProvider)
                      .updateStart(id, date, picked);
                  if (context.mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Nie udało się: $e')),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Usuń wpis'),
              onPressed: () async {
                final ok = await _confirmDelete(context, date);
                if (!ok) return;
                final id = _activeProfileId(ref);
                if (id == null) return;
                try {
                  await ref
                      .read(cycleRepositoryProvider)
                      .removeStart(id, date);
                  if (context.mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Nie udało się: $e')),
                    );
                  }
                }
              },
            ),
            ],
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickDate(BuildContext context, DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5, now.month, now.day),
      lastDate: now,
      locale: const Locale('pl', 'PL'),
      helpText: 'Zmień datę startu cyklu',
      cancelText: 'Anuluj',
      confirmText: 'Zapisz',
    );
  }

  Future<bool> _confirmDelete(BuildContext context, DateTime date) async {
    final fmt = DateFormat('d MMMM yyyy', 'pl_PL');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć wpis?'),
        content: Text('Czy na pewno usunąć start cyklu z ${fmt.format(date)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Usuń')),
        ],
      ),
    );
    return result ?? false;
  }
}
