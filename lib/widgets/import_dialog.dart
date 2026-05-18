import 'package:flutter/material.dart';

import '../models/person.dart';
import 'person_avatar.dart';

enum ImportMode { merge, replace }

class ImportTarget {
  ImportTarget._({
    this.existingProfileId,
    this.newProfileName,
    required this.mode,
  });

  final String? existingProfileId;
  final String? newProfileName;
  final ImportMode mode;

  bool get isNew => newProfileName != null;
}

class ImportDialog extends StatefulWidget {
  const ImportDialog({
    super.key,
    required this.persons,
    required this.activePersonId,
    required this.sourceName,
    required this.incomingCount,
  });

  final List<Person> persons;
  final String? activePersonId;
  final String? sourceName;
  final int incomingCount;

  static const String newSentinel = '__new__';

  static Future<ImportTarget?> show(
    BuildContext context, {
    required List<Person> persons,
    required String? activePersonId,
    required String? sourceName,
    required int incomingCount,
  }) {
    return showDialog<ImportTarget>(
      context: context,
      builder: (_) => ImportDialog(
        persons: persons,
        activePersonId: activePersonId,
        sourceName: sourceName,
        incomingCount: incomingCount,
      ),
    );
  }

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  String? _selectedTarget;
  late final TextEditingController _newNameCtrl;
  ImportMode _mode = ImportMode.merge;

  bool get _createNew => _selectedTarget == ImportDialog.newSentinel;

  @override
  void initState() {
    super.initState();
    _newNameCtrl = TextEditingController(text: widget.sourceName ?? '');

    final source = widget.sourceName?.toLowerCase().trim();
    Person? match;
    if (source != null && source.isNotEmpty) {
      for (final p in widget.persons) {
        if (p.name.toLowerCase().trim() == source) {
          match = p;
          break;
        }
      }
    }

    if (match != null) {
      _selectedTarget = match.id;
    } else if (source != null && source.isNotEmpty) {
      _selectedTarget = ImportDialog.newSentinel;
    } else {
      final active = widget.persons
          .where((p) => p.id == widget.activePersonId)
          .toList();
      _selectedTarget = active.isNotEmpty
          ? active.first.id
          : (widget.persons.isNotEmpty ? widget.persons.first.id : null);
    }
  }

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_createNew) return _newNameCtrl.text.trim().isNotEmpty;
    return _selectedTarget != null;
  }

  void _confirm() {
    if (!_isValid) return;
    final result = _createNew
        ? ImportTarget._(
            newProfileName: _newNameCtrl.text.trim(),
            mode: _mode,
          )
        : ImportTarget._(
            existingProfileId: _selectedTarget,
            mode: _mode,
          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Importuj cykle'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plik zawiera ${widget.incomingCount} ${_pluralCycles(widget.incomingCount)}.',
                style: theme.textTheme.bodyMedium,
              ),
              if (widget.sourceName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Oznaczone jako: „${widget.sourceName}"',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 16),
              Text('Importuj do profilu:', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              RadioGroup<String?>(
                groupValue: _selectedTarget,
                onChanged: (v) => setState(() => _selectedTarget = v),
                child: Column(
                  children: [
                    for (final p in widget.persons)
                      RadioListTile<String?>(
                        value: p.id,
                        title: Row(
                          children: [
                            PersonAvatar(person: p, size: 28),
                            const SizedBox(width: 10),
                            Expanded(child: Text(p.name)),
                            if (p.id == widget.activePersonId)
                              Text('aktywna', style: theme.textTheme.bodySmall),
                          ],
                        ),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    RadioListTile<String?>(
                      value: ImportDialog.newSentinel,
                      title: Row(
                        children: [
                          const Icon(Icons.person_add, size: 24),
                          const SizedBox(width: 10),
                          const Text('Utwórz nowy profil:'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _newNameCtrl,
                              enabled: _createNew,
                              maxLength: 30,
                              decoration: const InputDecoration(
                                isDense: true,
                                counterText: '',
                                hintText: 'nazwa',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ),
              ),
              if (!_createNew) ...[
                const SizedBox(height: 12),
                Text('Tryb:', style: theme.textTheme.titleSmall),
                RadioGroup<ImportMode>(
                  groupValue: _mode,
                  onChanged: (v) =>
                      setState(() => _mode = v ?? ImportMode.merge),
                  child: Row(
                    children: const [
                      Expanded(
                        child: RadioListTile<ImportMode>(
                          value: ImportMode.merge,
                          title: Text('Scal'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<ImportMode>(
                          value: ImportMode.replace,
                          title: Text('Zastąp'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _isValid ? _confirm : null,
          child: const Text('Importuj'),
        ),
      ],
    );
  }

  String _pluralCycles(int n) {
    if (n == 1) return 'cykl';
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'cykle';
    return 'cykli';
  }
}
