import 'package:flutter_test/flutter_test.dart';

import 'package:behangideaapp/core/services/streak_engine.dart';
import 'package:behangideaapp/core/utils/dates.dart';

void main() {
  final today = dateOnly(DateTime(2026, 8, 23));

  test('empty activity yields zero stats', () {
    final stats = StreakEngine.compute(const [], now: today);
    expect(stats.current, 0);
    expect(stats.best, 0);
    expect(stats.totalActiveDays, 0);
    expect(stats.lastActiveOn, isNull);
  });

  test('activity today gives streak of consecutive days', () {
    final activity = [
      DateTime(2026, 8, 21, 9),
      DateTime(2026, 8, 22, 15),
      DateTime(2026, 8, 23, 8),
    ];
    final stats = StreakEngine.compute(activity, now: today);
    expect(stats.current, 3);
    expect(stats.best, 3);
    expect(stats.totalActiveDays, 3);
  });

  test('yesterday keeps the streak alive but not extended', () {
    final activity = [
      DateTime(2026, 8, 20),
      DateTime(2026, 8, 22),
    ];
    final stats = StreakEngine.compute(activity, now: today);
    expect(stats.current, 1);
    expect(stats.best, 1);
  });

  test('gap resets current streak but remembers best', () {
    final activity = [
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 2),
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 4),
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 11),
    ];
    final stats = StreakEngine.compute(activity, now: today);
    expect(stats.current, 0);
    expect(stats.best, 4);
    expect(stats.totalActiveDays, 6);
  });

  test('multiple records on same day count once', () {
    final activity = [
      DateTime(2026, 8, 23, 7),
      DateTime(2026, 8, 23, 12),
      DateTime(2026, 8, 23, 20),
      DateTime(2026, 8, 22),
    ];
    final stats = StreakEngine.compute(activity, now: today);
    expect(stats.current, 2);
    expect(stats.totalActiveDays, 2);
  });

  test('streak older than yesterday is broken', () {
    final activity = [
      DateTime(2026, 8, 20),
      DateTime(2026, 8, 21),
    ];
    final stats = StreakEngine.compute(activity, now: today);
    expect(stats.current, 0);
    expect(stats.best, 2);
  });
}
