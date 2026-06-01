class CycleStats {
  static const int defaultWindow = 6;

  static DateTime? lastStart(List<DateTime> starts) {
    if (starts.isEmpty) return null;
    final sorted = [...starts]..sort();
    return sorted.last;
  }

  static List<int> cycleLengths(List<DateTime> starts, {int window = defaultWindow}) {
    if (starts.length < 2) return const [];
    final sorted = [...starts]..sort();
    final tail = sorted.length > window + 1
        ? sorted.sublist(sorted.length - window - 1)
        : sorted;
    final lengths = <int>[];
    for (var i = 1; i < tail.length; i++) {
      lengths.add(tail[i].difference(tail[i - 1]).inDays);
    }
    return lengths;
  }

  static int? averageLengthDays(List<DateTime> starts, {int window = defaultWindow}) {
    final lengths = cycleLengths(starts, window: window);
    if (lengths.isEmpty) return null;
    final sum = lengths.reduce((a, b) => a + b);
    return (sum / lengths.length).round();
  }

  static DateTime? predictedNextStart(List<DateTime> starts, {int window = defaultWindow}) {
    final last = lastStart(starts);
    final avg = averageLengthDays(starts, window: window);
    if (last == null || avg == null) return null;
    return last.add(Duration(days: avg));
  }

  /// Przewidywany dzień owulacji = przewidywany następny start - 14 dni
  /// (faza lutealna jest stała ~14 dni niezależnie od długości cyklu;
  /// faza folikularna jest zmienna).
  static DateTime? predictedOvulationDay(
    List<DateTime> starts, {
    int window = defaultWindow,
  }) {
    final next = predictedNextStart(starts, window: window);
    if (next == null) return null;
    return next.subtract(const Duration(days: 14));
  }

  /// Okno płodne — konserwatywne, uwzględnia niepewność prognozy owulacji
  /// (`ovulationUncertainty`, w dniach) plus życie gamet:
  /// - od `przewidywana owulacja − (5 + ovulationUncertainty)` (5 dni życia
  ///   plemników + niepewność owulacji),
  /// - do `przewidywana owulacja + (1 + ovulationUncertainty)` (1 dzień życia
  ///   jajka + niepewność owulacji).
  ///
  /// Dla domyślnej niepewności = 2 daje okno 11 dni. Dla 0 — 7 dni; dla 3 — 13 dni.
  /// Okno owulacji jest zawsze podzbiorem okna płodnego.
  static ({DateTime start, DateTime end})? predictedFertileWindow(
    List<DateTime> starts, {
    int window = defaultWindow,
    int ovulationUncertainty = 1,
  }) {
    final ovulation = predictedOvulationDay(starts, window: window);
    if (ovulation == null) return null;
    final u = ovulationUncertainty.clamp(0, 5);
    return (
      start: ovulation.subtract(Duration(days: 5 + u)),
      end: ovulation.add(Duration(days: 1 + u)),
    );
  }

  /// Okno owulacji — ±`ovulationUncertainty` dni od przewidywanego dnia.
  /// Dla domyślnej 2 daje 5 dni; dla 0 — pojedynczy dzień; dla 3 — 7 dni.
  static ({DateTime start, DateTime end})? predictedOvulationWindow(
    List<DateTime> starts, {
    int window = defaultWindow,
    int ovulationUncertainty = 1,
  }) {
    final ovulation = predictedOvulationDay(starts, window: window);
    if (ovulation == null) return null;
    final u = ovulationUncertainty.clamp(0, 5);
    return (
      start: ovulation.subtract(Duration(days: u)),
      end: ovulation.add(Duration(days: u)),
    );
  }

  /// Sprawdza czy dany dzień mieści się w przewidywanym oknie płodnym
  /// (włącznie z brzegami).
  static bool isInFertileWindow(
    DateTime day,
    List<DateTime> starts, {
    int window = defaultWindow,
    int ovulationUncertainty = 1,
  }) {
    return _isInRange(
      day,
      predictedFertileWindow(
        starts,
        window: window,
        ovulationUncertainty: ovulationUncertainty,
      ),
    );
  }

  /// Sprawdza czy dany dzień mieści się w oknie owulacji.
  static bool isInOvulationWindow(
    DateTime day,
    List<DateTime> starts, {
    int window = defaultWindow,
    int ovulationUncertainty = 1,
  }) {
    return _isInRange(
      day,
      predictedOvulationWindow(
        starts,
        window: window,
        ovulationUncertainty: ovulationUncertainty,
      ),
    );
  }

  static bool _isInRange(
    DateTime day,
    ({DateTime start, DateTime end})? range,
  ) {
    if (range == null) return false;
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(range.start.year, range.start.month, range.start.day);
    final e = DateTime(range.end.year, range.end.month, range.end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }
}
