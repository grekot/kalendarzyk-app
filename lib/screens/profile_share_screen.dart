import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/person_repository.dart';
import '../models/person.dart';
import '../providers/providers.dart';

class ProfileShareScreen extends ConsumerStatefulWidget {
  const ProfileShareScreen({super.key, required this.profile});
  final Person profile;

  @override
  ConsumerState<ProfileShareScreen> createState() => _ProfileShareScreenState();
}

class _ProfileShareScreenState extends ConsumerState<ProfileShareScreen> {
  late Future<List<ShareEntry>> _sharesFuture;

  String? _code;
  DateTime? _codeExpiresAt;
  ShareRole _codeRole = ShareRole.editor;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _sharesFuture = _loadShares();
  }

  Future<List<ShareEntry>> _loadShares() {
    return ref.read(personRepositoryProvider).listShares(widget.profile.id);
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .createInvite(widget.profile.id, role: _codeRole);
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

  Future<void> _changeRole(ShareEntry entry, ShareRole newRole) async {
    if (entry.role == newRole) return;
    try {
      await ref.read(personRepositoryProvider).updateShareRole(
            widget.profile.id,
            entry.userId,
            newRole,
          );
      setState(() => _sharesFuture = _loadShares());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się zmienić roli: $e')),
      );
    }
  }

  Future<void> _revoke(ShareEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cofnąć dostęp?'),
        content: Text(
          'Osoba „${entry.displayName.isEmpty ? "(bez nazwy)" : entry.displayName}" '
          'straci dostęp do tego profilu i jego cykli.',
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
        .revokeShare(widget.profile.id, entry.userId);
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
              'jest ${InviteRepoTtl.minutes} minut.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _RolePicker(
              value: _codeRole,
              onChanged: (r) => setState(() => _codeRole = r),
              enabled: _code == null,
            ),
            const SizedBox(height: 12),
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
                role: _codeRole,
                onRegenerate: _generate,
              ),
            const SizedBox(height: 24),
            Text('Osoby z dostępem:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            FutureBuilder<List<ShareEntry>>(
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
                    for (final s in shares) _ShareRow(
                      entry: s,
                      onRoleChanged: (r) => _changeRole(s, r),
                      onRevoke: () => _revoke(s),
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

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.entry,
    required this.onRoleChanged,
    required this.onRevoke,
  });

  final ShareEntry entry;
  final ValueChanged<ShareRole> onRoleChanged;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person),
        title: Text(
          entry.displayName.isEmpty ? '(bez nazwy)' : entry.displayName,
        ),
        subtitle: Text(_roleLabel(entry.role)),
        trailing: PopupMenuButton<_ShareAction>(
          tooltip: 'Zmień',
          onSelected: (action) {
            switch (action) {
              case _ShareAction.makeEditor:
                onRoleChanged(ShareRole.editor);
              case _ShareAction.makeViewer:
                onRoleChanged(ShareRole.viewer);
              case _ShareAction.revoke:
                onRevoke();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _ShareAction.makeEditor,
              enabled: entry.role != ShareRole.editor,
              child: const Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Daj prawo edycji'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _ShareAction.makeViewer,
              enabled: entry.role != ShareRole.viewer,
              child: const Row(
                children: [
                  Icon(Icons.visibility, size: 18),
                  SizedBox(width: 8),
                  Text('Ustaw na podgląd'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _ShareAction.revoke,
              child: Row(
                children: [
                  Icon(Icons.close,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Text('Cofnij dostęp',
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(ShareRole role) =>
      role == ShareRole.editor ? 'Edytor — może dodawać cykle' : 'Tylko podgląd';
}

enum _ShareAction { makeEditor, makeViewer, revoke }

class _RolePicker extends StatelessWidget {
  const _RolePicker({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final ShareRole value;
  final ValueChanged<ShareRole> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rola odbiorcy', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: !enabled,
              child: Opacity(
                opacity: enabled ? 1.0 : 0.5,
                child: RadioGroup<ShareRole>(
                  groupValue: value,
                  onChanged: (v) => onChanged(v ?? ShareRole.editor),
                  child: const Column(
                    children: [
                      RadioListTile<ShareRole>(
                        value: ShareRole.editor,
                        title: Text('Edytor'),
                        subtitle: Text(
                            'Może dodawać, zmieniać i usuwać daty cykli'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      RadioListTile<ShareRole>(
                        value: ShareRole.viewer,
                        title: Text('Tylko podgląd'),
                        subtitle:
                            Text('Widzi cykle, ale nie może ich zmieniać'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ),
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
    required this.role,
    required this.onRegenerate,
  });

  final String code;
  final DateTime expiresAt;
  final ShareRole role;
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
              role == ShareRole.editor
                  ? 'Kod parowania (Edytor)'
                  : 'Kod parowania (Podgląd)',
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

class InviteRepoTtl {
  static const minutes = 10;
}
