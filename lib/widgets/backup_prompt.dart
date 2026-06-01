import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/person.dart';
import '../providers/providers.dart';

/// Pomocnicze dialogi i funkcje do tworzenia kopii zapasowych profilu.
class BackupPrompt {
  /// Dialog „Wpis dodany. Czy zapisać kopię cykli?".
  /// Zwraca true gdy user wybierze „Tak, zapisz".
  static Future<bool> askAfterCycleAdded(
    BuildContext context, {
    required Person person,
    required DateTime addedDate,
  }) async {
    final fmt = DateFormat('d MMMM yyyy', 'pl_PL');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wpis dodany'),
        content: Text(
          'Dodano: ${fmt.format(addedDate)}.\n\n'
          'Czy chcesz teraz zapisać kopię cykli profilu „${person.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Nie'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save_alt),
            label: const Text('Tak, zapisz kopię'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Robi eksport JSON dla podanego profilu — na mobile przez share_plus,
  /// na desktop przez natywny „Zapisz jako". Pokazuje SnackBar z błędem lub
  /// potwierdzeniem. Bezpieczne do wywołania z dowolnego miejsca w UI.
  static Future<void> exportProfile(
    BuildContext context,
    WidgetRef ref,
    Person person,
  ) async {
    try {
      final repo = ref.read(cycleRepositoryProvider);
      final jsonStr =
          await repo.exportJson(person.id, personName: person.name);
      final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final safeName = person.name
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
          subject: 'Kalendarzyk — kopia zapasowa (${person.name})',
        );
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Zapisz kopię zapasową — ${person.name}',
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
}
