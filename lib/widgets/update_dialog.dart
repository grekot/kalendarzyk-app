import 'package:flutter/material.dart';

import '../data/update_checker.dart';

/// Pełnoekranowy dialog: pokazuje release notes, pobiera APK z paskiem
/// postępu, otwiera systemowy instalator. Zwraca `true` gdy user kliknął
/// „Pobierz" i pobranie się zakończyło (apka będzie kontynuowana w
/// systemowym instalatorze).
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info, required this.checker});

  final UpdateInfo info;
  final UpdateChecker checker;

  static Future<void> show(
    BuildContext context, {
    required UpdateInfo info,
    required UpdateChecker checker,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info, checker: checker),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double? _progress;
  bool _downloading = false;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await widget.checker.downloadAndInstall(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeMb = (widget.info.apkSize / (1024 * 1024)).toStringAsFixed(1);
    return AlertDialog(
      title: Text('Nowa wersja: ${widget.info.tag}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plik APK: $sizeMb MB',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (widget.info.notes.trim().isNotEmpty) ...[
                Text('Co nowego:', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  widget.info.notes.trim(),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              if (_downloading) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 4),
                Text(
                  _progress == null
                      ? 'Pobieranie…'
                      : 'Pobrano: ${(_progress! * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Później'),
        ),
        FilledButton.icon(
          onPressed: _downloading ? null : _download,
          icon: const Icon(Icons.download),
          label: const Text('Pobierz i zainstaluj'),
        ),
      ],
    );
  }
}
