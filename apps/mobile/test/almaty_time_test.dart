import 'package:darumen/api/almaty_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('almatyToday', () {
    test('before the UTC+5 day boundary stays on the same UTC day', () {
      // 2026-09-30T18:59:00Z + 5ч = 2026-09-30T23:59:00 Алматы — тот же день.
      final today = almatyToday(nowUtc: DateTime.utc(2026, 9, 30, 18, 59));
      expect(today, DateTime.utc(2026, 9, 30));
    });

    test('exactly at the UTC+5 day boundary rolls over to the next day', () {
      // 2026-09-30T19:00:00Z + 5ч = 2026-10-01T00:00:00 Алматы — уже следующий день.
      final today = almatyToday(nowUtc: DateTime.utc(2026, 9, 30, 19, 0));
      expect(today, DateTime.utc(2026, 10, 1));
    });

    test('one minute after the boundary is firmly the next day', () {
      final today = almatyToday(nowUtc: DateTime.utc(2026, 9, 30, 19, 1));
      expect(today, DateTime.utc(2026, 10, 1));
    });

    test('defaults to the current instant when nowUtc is omitted', () {
      final today = almatyToday();
      final expected = DateTime.now().toUtc().add(const Duration(hours: 5));
      expect(today, DateTime.utc(expected.year, expected.month, expected.day));
    });

    test('is independent of whether the input already carries a UTC flag', () {
      // DateTime.now() (локальное время устройства) должно нормализоваться через .toUtc() внутри хелпера.
      final local = DateTime.utc(2026, 1, 15, 10).toLocal();
      final today = almatyToday(nowUtc: local);
      expect(today, DateTime.utc(2026, 1, 15));
    });

    test('rolls over a month and a year boundary correctly', () {
      // 2025-12-31T19:30:00Z + 5ч = 2026-01-01T00:30:00 Алматы.
      final today = almatyToday(nowUtc: DateTime.utc(2025, 12, 31, 19, 30));
      expect(today, DateTime.utc(2026, 1, 1));
    });
  });

  group('formatApiDate', () {
    test('pads single-digit month and day to two digits', () {
      expect(formatApiDate(DateTime.utc(2026, 1, 5)), '2026-01-05');
    });

    test('formats a full date without padding needed', () {
      expect(formatApiDate(DateTime.utc(2026, 12, 31)), '2026-12-31');
    });

    test('uses the calendar fields of the value as is, without a time zone shift', () {
      expect(formatApiDate(DateTime(2026, 3, 9, 23, 59)), '2026-03-09');
    });

    test('round-trips with parseApiDate', () {
      expect(formatApiDate(parseApiDate('2028-02-29')!), '2028-02-29');
    });
  });

  group('almatyTodayString', () {
    test('combines almatyToday and formatApiDate', () {
      expect(almatyTodayString(nowUtc: DateTime.utc(2026, 9, 30, 19, 0)), '2026-10-01');
    });
  });

  group('parseApiDate', () {
    test('parses an exact yyyy-MM-dd into a UTC midnight date', () {
      expect(parseApiDate('2026-10-05'), DateTime.utc(2026, 10, 5));
    });

    test('returns null for anything that is not an exact calendar date', () {
      expect(parseApiDate(null), isNull);
      expect(parseApiDate(''), isNull);
      expect(parseApiDate('2026-10-05T10:00:00+00:00'), isNull);
      expect(parseApiDate('2026-02-29'), isNull, reason: '2026 — не високосный');
      expect(parseApiDate('05.10.2026'), isNull);
    });

    test('accepts a real leap day', () {
      expect(parseApiDate('2028-02-29'), DateTime.utc(2028, 2, 29));
    });

    test('rejects whitespace, missing zero padding and overflowing fields', () {
      expect(parseApiDate(' 2026-10-05'), isNull);
      expect(parseApiDate('2026-10-05 '), isNull);
      expect(parseApiDate('2026-1-05'), isNull);
      expect(parseApiDate('2026-04-31'), isNull);
      expect(parseApiDate('2026-00-10'), isNull);
      expect(parseApiDate('2026-10-00'), isNull);
    });

    test('the result is a UTC midnight, comparable with almatyToday', () {
      final parsed = parseApiDate('2026-10-01')!;
      expect(parsed.isUtc, isTrue);
      expect(parsed, almatyToday(nowUtc: DateTime.utc(2026, 10, 1, 8)));
    });
  });

  group('plannedDateWindow', () {
    test('spans today through today + 30 days inclusive', () {
      final window = plannedDateWindow(nowUtc: DateTime.utc(2026, 10, 1, 8));
      expect(window.start, DateTime.utc(2026, 10, 1));
      expect(window.end, DateTime.utc(2026, 10, 31));
    });

    test('the window starts on the Almaty day, not the UTC day, late in the UTC evening', () {
      // 2026-10-01T20:00Z = 2 октября 01:00 в Алматы
      final window = plannedDateWindow(nowUtc: DateTime.utc(2026, 10, 1, 20));
      expect(window.start, DateTime.utc(2026, 10, 2));
      expect(window.end, DateTime.utc(2026, 11, 1));
    });

    test('maxPlannedDays is the server constant 30', () {
      expect(maxPlannedDays, 30);
    });

    test('the window crosses a short month correctly', () {
      final window = plannedDateWindow(nowUtc: DateTime.utc(2027, 2, 10, 8));
      expect(window.end, DateTime.utc(2027, 3, 12));
    });
  });

  group('isPlannedDateInWindow', () {
    final nowUtc = DateTime.utc(2026, 10, 1, 8);

    test('accepts today (the start of the window)', () {
      expect(isPlannedDateInWindow('2026-10-01', nowUtc: nowUtc), isTrue);
    });

    test('accepts the end of the window (today + 30 days)', () {
      expect(isPlannedDateInWindow('2026-10-31', nowUtc: nowUtc), isTrue);
    });

    test('accepts a date in the middle of the window', () {
      expect(isPlannedDateInWindow('2026-10-15', nowUtc: nowUtc), isTrue);
    });

    test('rejects yesterday, one day before the window', () {
      expect(isPlannedDateInWindow('2026-09-30', nowUtc: nowUtc), isFalse);
    });

    test('rejects one day after the window', () {
      expect(isPlannedDateInWindow('2026-11-01', nowUtc: nowUtc), isFalse);
    });

    test('rejects a malformed date string instead of throwing', () {
      expect(isPlannedDateInWindow('not-a-date', nowUtc: nowUtc), isFalse);
    });

    test('rejects an empty string instead of throwing', () {
      expect(isPlannedDateInWindow('', nowUtc: nowUtc), isFalse);
    });

    // Сервер принимает plannedAt только в точном формате yyyy-MM-dd (DateOnly.TryParseExact, §4.7): всё остальное
    // он отклонит 422, поэтому и клиентская проверка не пропускает такие строки.
    test('a date with a time component is rejected: the API wants exactly yyyy-MM-dd', () {
      expect(isPlannedDateInWindow('2026-10-01T23:59:59+05:00', nowUtc: nowUtc), isFalse);
    });

    test('an unpadded date is rejected', () {
      expect(isPlannedDateInWindow('2026-10-1', nowUtc: nowUtc), isFalse);
    });

    test('a calendar-invalid date is rejected instead of rolling over to the next month', () {
      // DateTime.parse('2026-02-30') молча даёт 2 марта — окно проверяется по настоящей дате, а не по переполнению.
      expect(isPlannedDateInWindow('2026-02-30', nowUtc: DateTime.utc(2026, 2, 20, 8)), isFalse);
      expect(isPlannedDateInWindow('2026-13-01', nowUtc: nowUtc), isFalse);
    });

    test('surrounding whitespace is not accepted either', () {
      expect(isPlannedDateInWindow(' 2026-10-05', nowUtc: nowUtc), isFalse);
    });
  });
}
