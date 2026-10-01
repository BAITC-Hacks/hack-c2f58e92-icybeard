/// Даты API и «сегодня» по Алматы.
///
/// Сервер считает календарную дату по Asia/Almaty (фолбэк UTC+5; смещение постоянно круглый год, перехода на летнее
/// время нет), а не по часовому поясу устройства. Клиент обязан считать «сегодня» так же — иначе вечером по UTC
/// или на телефоне с чужим поясом окно дат разъедется с серверным и `confirm`/`reschedule` получат 422.
///
/// Правила, которые здесь закодированы:
/// - `plannedAt` в `confirm` и `reschedule` — ровно `yyyy-MM-dd`, сегодня ≤ plannedAt ≤ сегодня + [maxPlannedDays];
///   каждый `reschedule` открывает окно заново от текущего «сегодня»;
/// - день согласия на запись приёма (`ScribeConsent.day`) — тоже дата по Алматы.
///
/// Какие действия доступны в какой день (admit, no_show, overdue) клиент не вычисляет: кнопки берутся из
/// `progress.allowed` / `item.allowed`. Даты этапов маршрута показываются как пришли.
library;

/// Смещение Алматы от UTC — константа, не часовой пояс устройства.
const _almatyOffset = Duration(hours: 5);

/// Сколько дней вперёд от «сегодня» можно назначить дату госпитализации (`RouteJournal.cs`, включительно).
const maxPlannedDays = 30;

/// Точный формат дат API: четыре цифры года, две — месяца, две — дня.
final _apiDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Календарная дата в Алматы для момента [nowUtc] (по умолчанию — текущее время). Локальное время устройства
/// сначала нормализуется через `.toUtc()`, поэтому результат от часового пояса устройства не зависит.
/// Возвращается `DateTime.utc` с нулевым временем — только дата, пригодная для `isBefore`/`isAfter` и `==`.
DateTime almatyToday({DateTime? nowUtc}) {
  final almaty = (nowUtc ?? DateTime.now()).toUtc().add(_almatyOffset);
  return DateTime.utc(almaty.year, almaty.month, almaty.day);
}

/// Дата строкой `yyyy-MM-dd` — формат API для `plannedAt` и `day`. Берутся поля year/month/day самого [date]
/// без перевода поясов: передавайте дату, полученную из [almatyToday], [parseApiDate] или выбора в календаре.
String formatApiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Сегодняшняя дата в Алматы строкой `yyyy-MM-dd` — для значения по умолчанию в поле даты.
String almatyTodayString({DateTime? nowUtc}) => formatApiDate(almatyToday(nowUtc: nowUtc));

/// Строгий разбор даты API: только точный `yyyy-MM-dd` с настоящей календарной датой → `DateTime.utc` (полночь);
/// всё остальное — null, без исключения. Время, пробелы, формат без ведущих нулей и несуществующие даты
/// (`2026-02-30`, `2026-13-01`) отклоняются: сервер разбирает `plannedAt` так же строго и ответил бы 422.
DateTime? parseApiDate(String? value) {
  final match = value == null ? null : _apiDate.firstMatch(value);
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  // DateTime молча переносит переполнение (30 февраля → 2 марта): такая дата не настоящая
  return date.year == year && date.month == month && date.day == day ? date : null;
}

/// Окно допустимых дат госпитализации для `confirm`/`reschedule`: сегодня … сегодня + [maxPlannedDays]
/// включительно, оба конца — даты по Алматы. Границы для выбора даты в календаре.
({DateTime start, DateTime end}) plannedDateWindow({DateTime? nowUtc}) {
  final today = almatyToday(nowUtc: nowUtc);
  return (start: today, end: today.add(const Duration(days: maxPlannedDays)));
}

/// true — [plannedAt] разбирается [parseApiDate] и лежит в [plannedDateWindow]. Кривая или пустая строка — false,
/// а не исключение: форма просто не включает кнопку подтверждения.
bool isPlannedDateInWindow(String plannedAt, {DateTime? nowUtc}) {
  final date = parseApiDate(plannedAt);
  if (date == null) {
    return false;
  }
  final window = plannedDateWindow(nowUtc: nowUtc);
  return !date.isBefore(window.start) && !date.isAfter(window.end);
}
