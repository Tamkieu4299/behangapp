import '../utils/dates.dart';

class StreakStats {
  final int current;
  final int best;
  final int totalActiveDays;
  final DateTime? lastActiveOn;

  const StreakStats({
    required this.current,
    required this.best,
    required this.totalActiveDays,
    this.lastActiveOn,
  });

  static const StreakStats zero =
      StreakStats(current: 0, best: 0, totalActiveDays: 0);
}

class StreakEngine {
  static StreakStats compute(Iterable<DateTime> activity, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final days = activity.map(dateOnly).toSet().toList()..sort();
    if (days.isEmpty) return StreakStats.zero;

    var best = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      run = epochDay(days[i]) - epochDay(days[i - 1]) == 1 ? run + 1 : 1;
      if (run > best) best = run;
    }

    var current = 0;
    if (epochDay(today) - epochDay(days.last) <= 1) {
      current = 1;
      for (var i = days.length - 1; i > 0; i--) {
        if (epochDay(days[i]) - epochDay(days[i - 1]) == 1) {
          current++;
        } else {
          break;
        }
      }
    }

    return StreakStats(
      current: current,
      best: best,
      totalActiveDays: days.length,
      lastActiveOn: days.last,
    );
  }
}
