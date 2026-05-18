import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

const int jsonExportVersion = 2;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _formatIso(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime? _parseIso(String s) {
  try {
    final parts = s.split('-');
    if (parts.length != 3) return null;
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  } catch (_) {
    return null;
  }
}

class ImportPreview {
  final int currentCount;
  final int incomingCount;
  final int mergedCount;
  final String? incomingPersonName;
  ImportPreview({
    required this.currentCount,
    required this.incomingCount,
    required this.mergedCount,
    this.incomingPersonName,
  });
}

class ParsedImport {
  ParsedImport({required this.starts, this.personName});
  final List<DateTime> starts;
  final String? personName;
}

class CycleRepository {
  CycleRepository(this._client);
  final SupabaseClient _client;

  /// Strumień dat startu cyklu dla danego profilu, sortowany rosnąco.
  Stream<List<DateTime>> watch(String profileId) {
    return _client
        .from('cycles')
        .stream(primaryKey: ['id'])
        .eq('profile_id', profileId)
        .order('date')
        .map((rows) {
          final dates = rows
              .map((r) => _parseIso(r['date'].toString()))
              .whereType<DateTime>()
              .toSet()
              .toList()
            ..sort();
          return dates;
        });
  }

  Future<List<DateTime>> getStarts(String profileId) async {
    final rows = await _client
        .from('cycles')
        .select('date')
        .eq('profile_id', profileId)
        .order('date');
    final dates = (rows as List)
        .map((r) => _parseIso(r['date'].toString()))
        .whereType<DateTime>()
        .toSet()
        .toList()
      ..sort();
    return dates;
  }

  Future<void> addStart(String profileId, DateTime date) async {
    final iso = _formatIso(dateOnly(date));
    // upsert na unique (profile_id, date) — bezpieczne wielokrotne kliknięcie
    await _client.from('cycles').upsert(
      {
        'profile_id': profileId,
        'date': iso,
        'created_by': _client.auth.currentUser?.id,
      },
      onConflict: 'profile_id,date',
    );
  }

  Future<void> removeStart(String profileId, DateTime date) async {
    final iso = _formatIso(dateOnly(date));
    await _client
        .from('cycles')
        .delete()
        .eq('profile_id', profileId)
        .eq('date', iso);
  }

  Future<void> updateStart(
    String profileId,
    DateTime oldDate,
    DateTime newDate,
  ) async {
    // delete old + upsert new — bezpieczne nawet gdy newDate == oldDate
    await removeStart(profileId, oldDate);
    await addStart(profileId, newDate);
  }

  Future<void> clear(String profileId) async {
    await _client.from('cycles').delete().eq('profile_id', profileId);
  }

  Future<String> exportJson(String profileId, {String? personName}) async {
    final starts = await getStarts(profileId);
    return const JsonEncoder.withIndent('  ').convert({
      'version': jsonExportVersion,
      if (personName != null) 'person': {'name': personName},
      'starts': starts.map(_formatIso).toList(),
    });
  }

  ParsedImport parseImport(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) {
      throw const FormatException('Plik nie zawiera poprawnego JSON-a (oczekiwano obiektu).');
    }
    final startsRaw = decoded['starts'];
    if (startsRaw is! List) {
      throw const FormatException('Brakuje pola "starts" lub nie jest listą.');
    }
    final starts = <DateTime>[];
    for (final entry in startsRaw) {
      final d = _parseIso(entry.toString());
      if (d != null) starts.add(d);
    }
    String? personName;
    final personRaw = decoded['person'];
    if (personRaw is Map && personRaw['name'] is String) {
      personName = (personRaw['name'] as String).trim();
      if (personName.isEmpty) personName = null;
    }
    return ParsedImport(starts: starts, personName: personName);
  }

  Future<ImportPreview> previewImport(String profileId, String jsonStr) async {
    final parsed = parseImport(jsonStr);
    final current = (await getStarts(profileId)).toSet();
    final incoming = parsed.starts.toSet();
    final merged = current.union(incoming);
    return ImportPreview(
      currentCount: current.length,
      incomingCount: incoming.length,
      mergedCount: merged.length,
      incomingPersonName: parsed.personName,
    );
  }

  Future<void> importJson(
    String profileId,
    String jsonStr, {
    bool replace = false,
  }) async {
    final parsed = parseImport(jsonStr);
    if (replace) await clear(profileId);
    if (parsed.starts.isEmpty) return;
    final rows = parsed.starts
        .map((d) => {
              'profile_id': profileId,
              'date': _formatIso(dateOnly(d)),
              'created_by': _client.auth.currentUser?.id,
            })
        .toList();
    await _client.from('cycles').upsert(
      rows,
      onConflict: 'profile_id,date',
    );
  }
}
