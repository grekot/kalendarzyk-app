import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/person.dart';
import '../providers/providers.dart';

class ProfileShareScreen extends ConsumerStatefulWidget {
  const ProfileShareScreen({super.key, required this.profile});
  final Person profile;

  @override
  ConsumerState<ProfileShareScreen> createState() => _ProfileShareScreenState();
}

class _ProfileShareScreenState extends ConsumerState<ProfileShareScreen> {
  late Future<List<({String userId, String displayName})>> _sharesFuture;

  String? _code;
  DateTime? _codeExpiresAt;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _sharesFuture = _loadShares();
  }

  Future<List<({String userId, String displayName})>> _loadShares() {
    return ref.read(personRepositoryProvider).listShares(widget.profile.id);
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .createInvite(widget.profile.id);
      if (!mounted) return;
      setState(() {
        _code = invite.code;
        _codeExpiresAt = invite.expiresAt;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się: $e')),
      );
    }
  }

  Future<void> _revoke(String userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cofnąć dostęp?'),
        content: const Text(
          'Osoba straci dostęp do tego profilu i jego cykli.',
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
            child: const Text('Cofnij'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(personRepositoryProvider)
        .revokeShare(widget.profile.id, userId);
    setState(() => _sharesFuture = _loadShares());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Udostępnij: ${widget.profile.name}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Wygeneruj 6-cyfrowy kod parowania. Druga osoba wpisuje kod w '
              'swojej apce (Profile → przycisk „Dołącz przez kod"). Kod ważny '
              'jest ${_InviteRepoTtlText.minutes} minut.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_code == null)
              FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: const Icon(Icons.qr_code_2),
                label: Text(_generating
                    ? 'Generuję…'
                    : 'Wygeneruj kod parowania'),
              )
            else
              _CodeCard(
                code: _code!,
                expiresAt: _codeExpiresAt!,
                onRegenerate: _generate,
              ),
            const SizedBox(height: 24),
            Text('Osoby z dostępem:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            FutureBuilder<List<({String userId, String displayName})>>(
              future: _sharesFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Text('Błąd: ${snap.error}');
                }
                final shares = snap.data ?? const [];
                if (shares.isEmpty) {
                  return Text(
                    'Brak — tylko Ty masz dostęp.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final s in shares)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(
                            s.displayName.isEmpty
                                ? '(bez nazwy)'
                                : s.displayName,
                          ),
                          trailing: IconButton(
                            tooltip: 'Cofnij dostęp',
                            icon: Icon(Icons.close,
                                color: theme.colorScheme.error),
                            onPressed: () => _revoke(s.userId),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.code,
    required this.expiresAt,
    required this.onRegenerate,
  });

  final String code;
  final DateTime expiresAt;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('HH:mm', 'pl_PL');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kod parowania',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(
              _spaced(code),
              style: theme.textTheme.displaySmall?.copyWith(
                letterSpacing: 4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Ważny do ${fmt.format(expiresAt.toLocal())}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Skopiowano')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Skopiuj'),
                ),
                TextButton.icon(
                  onPressed: onRegenerate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Nowy kod'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _spaced(String code) {
    if (code.length != 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }
}

class _InviteRepoTtlText {
  static const minutes = 10;
}
