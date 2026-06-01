import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';

class AddCycleStartDialog extends ConsumerWidget {
  const AddCycleStartDialog({super.key});

  /// Zwraca dodaną datę gdy user pomyślnie zapisze cykl,
  /// `null` gdy anuluje lub coś pójdzie nie tak.
  static Future<DateTime?> show(BuildContext context) {
    return showDialog<DateTime>(
      context: context,
      builder: (_) => const AddCycleStartDialog(),
    );
  }

  Future<void> _addStart(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
  ) async {
    final activeId = ref.read(activePersonIdProvider);
    if (activeId == null) {
      Navigator.of(context).pop();
      return;
    }
    try {
      await ref.read(cycleRepositoryProvider).addStart(activeId, date);
      if (context.mounted) {
        Navigator.of(context).pop(date);
        _showAddedSnack(context, date);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nie udało się dodać: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Dodaj początek menstruacji'),
      content: const Text('Wybierz datę startu cyklu.'),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.event),
              label: const Text('Podaj datę'),
              onPressed: () async {
                final picked = await _pickDate(context);
                if (picked != null && context.mounted) {
                  await _addStart(context, ref, picked);
                }
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.today),
              label: const Text('Dzisiejsza data'),
              onPressed: () => _addStart(context, ref, DateTime.now()),
            ),
          ],
        ),
      ],
    );
  }

  static Future<DateTime?> _pickDate(BuildContext context) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5, now.month, now.day),
      lastDate: now,
      locale: const Locale('pl', 'PL'),
      helpText: 'Wybierz datę startu cyklu',
      cancelText: 'Anuluj',
      confirmText: 'Wybierz',
    );
  }

  static void _showAddedSnack(BuildContext context, DateTime date) {
    final fmt = DateFormat('d MMMM yyyy', 'pl_PL');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dodano: ${fmt.format(date)}')),
    );
  }
}
