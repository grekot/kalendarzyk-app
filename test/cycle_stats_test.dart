import 'package:flutter_test/flutter_test.dart';
import 'package:kalendazyk/data/cycle_stats.dart';

void main() {
  group('CycleStats.lastStart', () {
    test('null gdy pusta lista', () {
      expect(CycleStats.lastStart(const []), isNull);
    });

    test('zwraca najpóźniejszą datę niezależnie od kolejności', () {
      final starts = [
        DateTime(2026, 1, 1),
        DateTime(2026, 3, 1),
        DateTime(2026, 2, 1),
      ];
      expect(CycleStats.lastStart(starts), DateTime(2026, 3, 1));
    });
  });

  group('CycleStats.averageLengthDays', () {
    test('null przy mniej niż 2 wpisach', () {
      expect(CycleStats.averageLengthDays(const []), isNull);
      expect(CycleStats.averageLengthDays([DateTime(2026, 1, 1)]), isNull);
    });

    test('przy 2 wpisach = różnica w dniach', () {
      final starts = [DateTime(2026, 1, 1), DateTime(2026, 1, 29)];
      expect(CycleStats.averageLengthDays(starts), 28);
    });

    test('uwzględnia tylko ostatnie window+1 startów', () {
      // 8 startów, okno 6 -> bierze ostatnie 7 startów, czyli ostatnie 6 cykli (długości)
      final starts = [
        DateTime(2025, 1, 1),  // ignored
        DateTime(2025, 6, 1),  // ignored
        DateTime(2025, 7, 1),  // 1. cykl 30d
        DateTime(2025, 7, 31), // 2. cykl 30d
        DateTime(2025, 8, 30), // 3. cykl 30d
        DateTime(2025, 9, 29), // 4. cykl 30d
        DateTime(2025, 10, 29),// 5. cykl 30d
        DateTime(2025, 11, 28),// 6. cykl 30d
      ];
      expect(CycleStats.averageLengthDays(starts), 30);
    });
  });

  group('CycleStats.predictedNextStart', () {
    test('null gdy brak średniej', () {
      expect(CycleStats.predictedNextStart(const []), isNull);
      expect(CycleStats.predictedNextStart([DateTime(2026, 1, 1)]), isNull);
    });

    test('ostatni start + średnia długość', () {
      final starts = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 29),
        DateTime(2026, 2, 26),
      ];
      expect(CycleStats.predictedNextStart(starts), DateTime(2026, 3, 26));
    });
  });
}
