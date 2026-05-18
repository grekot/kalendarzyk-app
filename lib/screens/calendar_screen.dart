import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../data/cycle_repository.dart';
import '../data/cycle_stats.dart';
import '../providers/providers.dart';
import '../theme.dart';
import '../widgets/cycle_day_sheet.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _focusedDay;
  CalendarFormat _format = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _focusedDay = dateOnly(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final cyclesAsync = ref.watch(cyclesProvider);
    final starts = cyclesAsync.valueOrNull ?? const <DateTime>[];
    final startsSet = starts.map(dateOnly).toSet();
    final predicted = CycleStats.predictedNextStart(starts);
    final today = dateOnly(DateTime.now());
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalendarz cykli'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: TableCalendar<DateTime>(
                  locale: 'pl_PL',
                  firstDay: DateTime(now.year - 3, 1, 1),
                  lastDay: DateTime(now.year + 1, 12, 31),
                  focusedDay: _focusedDay,
                  currentDay: today,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  availableCalendarFormats: const {
                    CalendarFormat.month: 'Miesiąc',
                    CalendarFormat.twoWeeks: '2 tyg.',
                    CalendarFormat.week: 'Tydzień',
                  },
                  calendarFormat: _format,
                  onFormatChanged: (f) => setState(() => _format = f),
                  onPageChanged: (f) => _focusedDay = f,
                  eventLoader: (day) =>
                      startsSet.contains(dateOnly(day)) ? [day] : const [],
                  selectedDayPredicate: (day) =>
                      predicted != null && dateOnly(day) == predicted,
                  onDaySelected: (selected, focused) async {
                    final d = dateOnly(selected);
                    setState(() => _focusedDay = focused);
                    if (startsSet.contains(d)) {
                      await CycleDaySheet.show(context, d);
                    }
                  },
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                    selectedDecoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: CycleColors.predicted, width: 2),
                    ),
                    selectedTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    markersMaxCount: 1,
                    markerDecoration: const BoxDecoration(
                      color: CycleColors.period,
                      shape: BoxShape.circle,
                    ),
                  ),
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, day, events) {
                      if (events.isEmpty) return null;
                      return Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: CycleColors.period,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${day.day}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const _Legend(),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'Wskazówka: dotknij zaznaczonego dnia żeby edytować lub usunąć wpis.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _legendItem(context, CycleColors.period, 'Start cyklu', filled: true),
          _legendItem(context, CycleColors.predicted, 'Przewidywany start', filled: false),
        ],
      ),
    );
  }

  Widget _legendItem(BuildContext context, Color color, String label, {required bool filled}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: filled ? color : null,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: color, width: 2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
