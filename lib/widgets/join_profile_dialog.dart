import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class JoinProfileDialog extends ConsumerStatefulWidget {
  const JoinProfileDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String?>(
      context: context,
      builder: (_) => const JoinProfileDialog(),
    );
  }

  @override
  ConsumerState<JoinProfileDialog> createState() =>
      _JoinProfileDialogState();
}

class _JoinProfileDialogState extends ConsumerState<JoinProfileDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final code = _ctrl.text.replaceAll(RegExp(r'\s+'), '');
    if (code.length != 6) {
      setState(() => _error = 'Kod musi mieć 6 cyfr.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profileId =
          await ref.read(inviteRepositoryProvider).redeemInvite(code);
      if (!mounted) return;
      Navigator.of(context).pop(profileId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dołącz przez kod'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Wpisz 6-cyfrowy kod parowania który dostałeś/aś od osoby '
            'udostępniającej profil.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: 'Kod (6 cyfr)',
              errorText: _error,
              counterText: '',
            ),
            style: const TextStyle(letterSpacing: 4, fontSize: 20),
            textAlign: TextAlign.center,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Łączę…' : 'Dołącz'),
        ),
      ],
    );
  }
}
