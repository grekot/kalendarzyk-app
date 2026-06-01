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

  group('CycleStats.predictedOvulationDay', () {
    test('null gdy brak prognozy', () {
      expect(CycleStats.predictedOvulationDay(const []), isNull);
    });

    test('14 dni przed przewidywanym startem', () {
      // cykl 28-dniowy → next start 2026-03-26 → owulacja 2026-03-12
      final starts = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 29),
        DateTime(2026, 2, 26),
      ];
      expect(
        CycleStats.predictedOvulationDay(starts),
        DateTime(2026, 3, 12),
      );
    });

    test('dla dłuższego cyklu owulacja przesuwa się proporcjonalnie', () {
      // cykl 30-dniowy → next start = last + 30 → owulacja 16 dni od last
      final starts = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 31),
      ];
      // next = 2026-03-02, ovulation = 2026-02-16
      expect(
        CycleStats.predictedOvulationDay(starts),
        DateTime(2026, 2, 16),
      );
    });
  });

  group('CycleStats.predictedFertileWindow', () {
    test('null gdy brak prognozy', () {
      expect(CycleStats.predictedFertileWindow(const []), isNull);
    });

    test('9-dniowe okno przy domyślnej ±1: 6 przed + dzień owulacji + 2 po', () {
      // owulacja 2026-03-12 → okno [2026-03-06 .. 2026-03-14]
      final starts = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 29),
        DateTime(2026, 2, 26),
      ];
      final fw = CycleStats.predictedFertileWindow(starts);
      expect(fw, isNotNull);
      expect(fw!.start, DateTime(2026, 3, 6));
      expect(fw.end, DateTime(2026, 3, 14));
      expect(fw.end.difference(fw.start).inDays + 1, 9);
    });

    test('okno owulacji jest podzbiorem okna płodnego', () {
      final starts = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 29),
        DateTime(2026, 2, 26),
      ];
      final fw = CycleStats.predictedFertileWindow(starts)!;
      final ow = CycleStats.predictedOvulationWindow(starts)!;
      expect(ow.start.isAtSameMomentAs(fw.start) || ow.start.isAfter(fw.start),
          isTrue);
      expect(
          ow.end.isAtSameMomentAs(fw.end) || ow.end.isBefore(fw.end), isTrue);
    });
  });

  group('CycleStats.predictedOvulationWindow', () {
    test('null gdy brak prognozy', () {
      expect(CycleStats.predictedOvulationWindow(const []), isNull);
    });

    test('domyślnie ±1 dzień od dnia owulacji (3 dni)', () {
      // owulacja 2026-03-12 → window [2026-03-11 .. 2026-03-13]
      final starts = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 29),
        DateTime(2026, 2, 26),
      ];
      final ow = CycleStats.predictedOvulationWindow(starts);
      expect(ow, isNotNull);
      expect(ow!.start, DateTime(2026, 3, 11));
      expect(ow.end, DateTime(2026, 3, 13));
      expect(ow.end.difference(ow.start).inDays + 1, 3);
    });

    test('±0 niepewności — pojedynczy dzień', () {
      final starts = [DateTime(2026, 1, 1), DateTime(2026, 1, 29)];
      // owulacja 2026-02-12
      final ow = CycleStats.predictedOvulationWindow(starts,
          ovulationUncertainty: 0);
      expect(ow!.start, DateTime(2026, 2, 12));
      expect(ow.end, DateTime(2026, 2, 12));
      expect(ow.end.difference(ow.start).inDays + 1, 1);
    });

    test('±3 niepewności — 7 dni', () {
      final starts = [DateTime(2026, 1, 1), DateTime(2026, 1, 29)];
      final ow = CycleStats.predictedOvulationWindow(starts,
          ovulationUncertainty: 3);
      expect(ow!.start, DateTime(2026, 2, 9));
      expect(ow.end, DateTime(2026, 2, 15));
      expect(ow.end.difference(ow.start).inDays + 1, 7);
    });
  });

  group('CycleStats.predictedFertileWindow z różną niepewnością', () {
    final starts = [DateTime(2026, 1, 1), DateTime(2026, 1, 29)];
    // owulacja 2026-02-12

    test('±0 niepewności → fertile = 7 dni [-5..+1]', () {
      final fw = CycleStats.predictedFertileWindow(starts,
          ovulationUncertainty: 0);
      expect(fw!.start, DateTime(2026, 2, 7));
      expect(fw.end, DateTime(2026, 2, 13));
      expect(fw.end.difference(fw.start).inDays + 1, 7);
    });

    test('±3 niepewności → fertile = 13 dni [-8..+4]', () {
      final fw = CycleStats.predictedFertileWindow(starts,
          ovulationUncertainty: 3);
      expect(fw!.start, DateTime(2026, 2, 4));
      expect(fw.end, DateTime(2026, 2, 16));
      expect(fw.end.difference(fw.start).inDays + 1, 13);
    });
  });

  group('CycleStats.isInOvulationWindow (±2 explicit)', () {
    final starts = [
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 29),
      DateTime(2026, 2, 26),
    ];
    // window owulacji [2026-03-10 .. 2026-03-14] przy ovulationUncertainty=2
    test('w środku — dzień owulacji', () {
      expect(
        CycleStats.isInOvulationWindow(DateTime(2026, 3, 12), starts,
            ovulationUncertainty: 2),
        isTrue,
      );
    });
    test('brzeg -2 dni', () {
      expect(
        CycleStats.isInOvulationWindow(DateTime(2026, 3, 10), starts,
            ovulationUncertainty: 2),
        isTrue,
      );
    });
    test('brzeg +2 dni', () {
      expect(
        CycleStats.isInOvulationWindow(DateTime(2026, 3, 14), starts,
            ovulationUncertainty: 2),
        isTrue,
      );
    });
    test('-3 dni — poza', () {
      expect(
        CycleStats.isInOvulationWindow(DateTime(2026, 3, 9), starts,
            ovulationUncertainty: 2),
        isFalse,
      );
    });
    test('+3 dni — poza', () {
      expect(
        CycleStats.isInOvulationWindow(DateTime(2026, 3, 15), starts,
            ovulationUncertainty: 2),
        isFalse,
      );
    });
  });

  group('CycleStats.isInFertileWindow (domyślnie ±1)', () {
    final starts = [
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 29),
      DateTime(2026, 2, 26),
    ];
    // okno [2026-03-06 .. 2026-03-14]
    test('w środku okna', () {
      expect(
        CycleStats.isInFertileWindow(DateTime(2026, 3, 10), starts),
        isTrue,
      );
    });
    test('brzeg początkowy (owulacja −6)', () {
      expect(
        CycleStats.isInFertileWindow(DateTime(2026, 3, 6), starts),
        isTrue,
      );
    });
    test('brzeg końcowy (owulacja +2)', () {
      expect(
        CycleStats.isInFertileWindow(DateTime(2026, 3, 14), starts),
        isTrue,
      );
    });
    test('dzień przed', () {
      expect(
        CycleStats.isInFertileWindow(DateTime(2026, 3, 5), starts),
        isFalse,
      );
    });
    test('dzień po', () {
      expect(
        CycleStats.isInFertileWindow(DateTime(2026, 3, 15), starts),
        isFalse,
      );
    });
  });
}
