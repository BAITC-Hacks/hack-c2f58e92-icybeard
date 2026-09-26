import '../l10n/strings.dart';
import 'format.dart';

/// Группа строк одного дня: заголовок «Сегодня · Вчера · 22 сентября» и элементы, свежие первыми.
class DayGroup<T> {
  const DayGroup(this.label, this.items);

  final String label;
  final List<T> items;
}

/// Заголовок дня относительно `now`; год добавляется, если день не в текущем году.
String dayHeading(DateTime day, S s, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final base = DateTime(today.year, today.month, today.day);
  final diff = base.difference(DateTime(day.year, day.month, day.day)).inDays;
  if (diff == 0) {
    return s.today;
  }
  if (diff == 1) {
    return s.yesterday;
  }
  final text = '${day.day} ${s.monthGenitive(day.month)}';
  return day.year == today.year ? text : '$text ${day.year}';
}

/// Группировка по локальному дню (ISO-дата или timestamp); порядок элементов внутри группы — как во входе,
/// группы — от свежего дня к старому. Элементы без даты попадают в последнюю группу «—».
List<DayGroup<T>> groupByDay<T>(Iterable<T> items, String? Function(T item) at, S s, {DateTime? now}) {
  final buckets = <DateTime?, List<T>>{};
  for (final item in items) {
    buckets.putIfAbsent(localDay(at(item)), () => []).add(item);
  }
  final days = buckets.keys.whereType<DateTime>().toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days) DayGroup(dayHeading(day, s, now: now), buckets[day]!),
    if (buckets.containsKey(null)) DayGroup('—', buckets[null]!),
  ];
}
