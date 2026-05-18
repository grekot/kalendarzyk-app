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
}
