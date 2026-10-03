import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  final monday = LocalDate(2026, 9, 14);

  test('weekday and month names are German', () {
    expect(weekdayLong(monday), 'Montag');
    expect(weekdayShort(monday), 'Mo.');
    expect(weekdayTwoLetters(monday), 'Mo');
    expect(weekdayLong(LocalDate(2026, 9, 20)), 'Sonntag');
    expect(monthLong(3), 'März');
    expect(monthLong(12), 'Dezember');
  });

  test('long, short and month-group formats follow the design', () {
    expect(formatDateLong(monday), 'Montag, 14. September');
    expect(formatDateShort(monday), 'Mo., 14. Sep.');
    expect(formatDateShort(LocalDate(2026, 8, 1)), 'Sa., 1. Aug.');
    expect(formatDayMonth(LocalDate(2026, 3, 5)), '5. März');
    expect(formatMonthYearUpper(monday), 'SEPTEMBER 2026');
  });

  test('a different year is appended only when asked for', () {
    final old = LocalDate(2025, 12, 31);
    expect(formatDateShort(old), 'Mi., 31. Dez.');
    expect(formatDateShort(old, contextYear: 2026), 'Mi., 31. Dez. 2025');
    expect(formatDateShort(old, contextYear: 2025), 'Mi., 31. Dez.');
  });

  test('relative days: today, yesterday, weekday within a week, else date', () {
    final today = LocalDate(2026, 9, 14);
    expect(formatRelativeDay(today, today), 'Heute');
    expect(formatRelativeDay(today.addDays(-1), today), 'Gestern');
    expect(formatRelativeDay(today.addDays(-2), today), 'Samstag');
    expect(formatRelativeDay(today.addDays(-6), today), 'Dienstag');
    expect(formatRelativeDay(today.addDays(-7), today), 'Mo., 7. Sep.');
    expect(
      formatRelativeDay(LocalDate(2025, 9, 14), today),
      'So., 14. Sep. 2025',
    );
  });

  test('month and year boundaries use calendar days', () {
    final today = LocalDate(2026, 1, 2);
    expect(formatRelativeDay(LocalDate(2025, 12, 31), today), 'Mittwoch');
    expect(
      formatRelativeDay(LocalDate(2025, 12, 26), today),
      'Fr., 26. Dez. 2025',
    );
  });
}
