import '../l10n/strings.dart';

/// Форматтеры чисел, дат и имён для экранов. Даты API — ISO `yyyy-MM-dd` или timestamp; показываем `dd.MM.yyyy`
/// без зависимости от локальных данных intl (шаблон одинаков для ru и kk). Правила совпадают с веб-клиентом
/// (`apps/web/src/lib/format.ts`, `lib/route.ts`).
String days(double? value) => value == null ? '—' : value.round().toString();

/// Модельное число дней с приставкой «≈»: `≈ 47`; без значения — «—». Единица («дн.») идёт отдельно.
String approxDays(double? value) => value == null ? '—' : '≈ ${days(value)}';

/// Дни с короткой единицей: «21 дн.» / «21 күн»; без значения — «—». Слово «дней» не используется.
String daysWithUnit(double? value, S s) => value == null ? '—' : '${days(value)} ${s.daysUnit}';

/// Разница в днях по тем же округлённым значениям, что видны на экране: `round(baseline) − round(other)`
/// («≈ 4 и ≈ 2 → на 2 дн.»). Больше нуля — [other] быстрее, меньше — дольше, ноль — «как в вашей больнице».
/// null — нет одного из значений.
int? roundedDaysDiff(double? baseline, double? other) => baseline == null || other == null ? null : baseline.round() - other.round();

/// Риск отказа относительно среднего по стране (11 % направлений заканчиваются отказом).
enum RefusalLevel { below, average, above }

/// Уровень риска отказа: от 0.165 — выше среднего, до 0.055 включительно — ниже, между — около среднего;
/// null — нет значения. Пороги как у веба (`refusalWords`).
RefusalLevel? refusalLevel(double? p) {
  if (p == null || p.isNaN) {
    return null;
  }
  return p >= 0.165 ? RefusalLevel.above : (p <= 0.055 ? RefusalLevel.below : RefusalLevel.average);
}

/// Риск отказа словами на языке интерфейса («выше среднего»); показывается вместо процента, когда организация не
/// встречалась модели при обучении (`refusalOrgInTraining == false`). Без значения — «—».
String refusalWords(S s, double? p) => switch (refusalLevel(p)) {
      RefusalLevel.above => s.refusalAboveAverage,
      RefusalLevel.average => s.refusalAroundAverage,
      RefusalLevel.below => s.refusalBelowAverage,
      null => '—',
    };

/// Риск отказа показывается красным: больше 20 %, как в вебе (`pRefusal > 0.2` на странице пациента и в ассистенте
/// направления) — и процентом, и словами.
bool refusalHigh(double p) => p > 0.2;

/// Первая буква — заглавная, остальные как есть («риск отказа» → «Риск отказа»): так StatusChip показывает подписи
/// словаря, которые хранятся строчными.
String capitalizeFirst(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

String pct(double? value) => value == null ? '—' : '${(value * 100).round()} %';

/// Целое число с тонкими пробелами между разрядами: 11 330 078.
String thousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write('\u202f');
    }
    buffer.write(digits[i]);
  }
  return value < 0 ? '−$buffer' : buffer.toString();
}

/// Дата маршрута (этапы, план госпитализации, срок анализа) `дд.мм.гггг` из календарной части ISO-значения — без
/// пересчёта в часовой пояс устройства, как в вебе: одна запись на обоих клиентах показывает один день. Пусто — «—»,
/// незнакомый формат — как есть.
String routeDate(String? iso) {
  if (iso == null || iso.isEmpty) {
    return '—';
  }
  final match = _isoDate.firstMatch(iso);
  return match == null ? iso : '${match[3]}.${match[2]}.${match[1]}';
}

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// Момент или дата `дд.мм.гггг`; момент со временем — в часовом поясе устройства (журнал, уведомления).
String dateShort(String? iso) {
  if (iso == null || iso.isEmpty) {
    return '—';
  }
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso;
  }
  final local = iso.length > 10 ? parsed.toLocal() : parsed;
  return '${_two(local.day)}.${_two(local.month)}.${local.year}';
}

String dateTimeShort(String? iso) {
  if (iso == null || iso.isEmpty) {
    return '—';
  }
  final parsed = DateTime.tryParse(iso)?.toLocal();
  if (parsed == null) {
    return iso;
  }
  return '${dateShort(iso)} ${_two(parsed.hour)}:${_two(parsed.minute)}';
}

/// Локальная дата события без времени (полночь того дня) — для сравнения по дням, например возраста среза данных;
/// дата без времени (`yyyy-MM-dd`) берётся как есть, момент переводится во время устройства.
DateTime? localDay(String? iso) {
  if (iso == null || iso.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return null;
  }
  final local = iso.length > 10 ? parsed.toLocal() : parsed;
  return DateTime(local.year, local.month, local.day);
}

/// ИИН показывается только маской: последние четыре цифры, никогда полностью.
String maskIin(String? iin) => iin == null || iin.length < 4 ? '—' : '•••• ${iin.substring(iin.length - 4)}';

String _two(int value) => value.toString().padLeft(2, '0');

/// Организационно-правовые формы, которые убираются из начала юридического имени (без учёта регистра, только целым
/// словом: за формой идёт пробел, кавычка или конец строки). Список веба (`format.ts`) в его порядке — длинные раньше
/// коротких — плюс казахские формы для локализованного справочника.
const _legalForms = [
  'Коммунальное государственное предприятие на праве хозяйственного ведения',
  'Государственное коммунальное предприятие на праве хозяйственного ведения',
  'Республиканское государственное предприятие на праве хозяйственного ведения',
  'Государственное коммунальное казённое предприятие',
  'Государственное коммунальное казенное предприятие',
  'Коммунальное государственное казённое предприятие',
  'Коммунальное государственное казенное предприятие',
  'Коммунальное государственное предприятие',
  'Государственное коммунальное предприятие',
  'Республиканское государственное предприятие',
  'Товарищество с ограниченной ответственностью',
  'Некоммерческое акционерное общество',
  'Акционерное общество',
  'Коммунальное государственное учреждение',
  'Республиканское государственное учреждение',
  'Государственное учреждение',
  'Частное учреждение',
  'Учреждение',
  'Индивидуальный предприниматель',
  'КГП на ПХВ',
  'ГКП на ПХВ',
  'РГП на ПХВ',
  'КГППХВ',
  'ГКППХВ',
  'РГППХВ',
  'ГККП',
  'КГП',
  'ГКП',
  'РГП',
  'КГУ',
  'РГУ',
  'ТОО',
  'НАО',
  'АО',
  'ГУ',
  'ЧУ',
  'ИП',
  'Шаруашылық жүргізу құқығындағы коммуналдық мемлекеттік кәсіпорын',
  'Шаруашылық жүргізу құқығындағы республикалық мемлекеттік кәсіпорын',
  'Жауапкершілігі шектеулі серіктестік',
  'Коммерциялық емес акционерлік қоғам',
  'Акционерлік қоғам',
  'Мемлекеттік мекеме',
  'Жеке мекеме',
  'Мекеме',
  'ШЖҚ КМК',
  'ШЖҚ РМК',
  'ЖШС',
  'КеАҚ',
  'АҚ',
  'ММ',
];

const _openQuotes = '"«„“';
const _closeQuotes = '"»“”';

/// Граница формы: пробел или открывающая кавычка сразу за ней.
final _formBoundary = RegExp('[\\s"«„“]', unicode: true);

/// «на праве хозяйственного ведения "…"» встречается и без формы собственности впереди.
final _rightOfPattern = RegExp(r'^на праве (хозяйственного ведения|оперативного управления)\s*', caseSensitive: false, unicode: true);

/// Хвост после закрывающей кавычки — принадлежность («Управления здравоохранения…», «на праве…»): по нему узнаётся
/// конец имени.
final _affiliationTail = RegExp(r'^(на праве|управлени|министерств|комитет|департамент|акимат|уоз|уз |мз |ру |гу )', caseSensitive: false, unicode: true);

/// Фрагменты «ордена "Знак Почета"» внутри имени (граница слова — не буква перед «ордена»).
final _orderPattern = RegExp(r'(?<!\p{L})ордена\s+["«„“][^"»“”]*["»“”]\s*', caseSensitive: false, unicode: true);

final _spaces = RegExp(r'\s{2,}');

/// Короткое имя организации для списков, карточек и уведомлений: без организационно-правовой формы, «на праве …» и
/// принадлежности. `ТОО "Достар Мед"` → `Достар Мед`; `КГП на ПХВ "Алматинский онкологический центр" Управления
/// общественного здравоохранения города Алматы` → `Алматинский онкологический центр`; `Реабилитационный центр
/// "Алау" Управления …` (внешняя кавычка потеряна) → `Реабилитационный центр "Алау"`. Полное юридическое имя
/// остаётся для деталей (лист по тапу, `OrgName`). Правило и векторы — как в вебе (`shortOrgName` в `format.ts`),
/// плюс казахские формы. null и пустая строка — `''`; если сокращать нечего — имя без крайних пробелов.
String shortOrgName(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) {
    return '';
  }
  final rest = _stripLegalForm(trimmed).replaceFirst(_rightOfPattern, '');
  if (rest.isEmpty) {
    return trimmed;
  }
  var short = rest;
  if (_openQuotes.contains(rest[0])) {
    final close = _closingQuote(rest);
    short = close > 0 ? rest.substring(1, close) : rest.substring(1);
    // нечётное число кавычек внутри — внешняя закрывающая слилась с внутренней («…центр "Алау" Управления…»)
    final inner = short.split('').where((ch) => _closeQuotes.contains(ch) || _openQuotes.contains(ch)).length;
    if (close > 0 && inner.isOdd) {
      short = rest.substring(1, close + 1);
    }
  }
  short = short.replaceAll(_orderPattern, '').replaceAll(_spaces, ' ').trim();
  return short.isEmpty ? trimmed : short;
}

String _stripLegalForm(String name) {
  final lower = name.toLowerCase();
  for (final form in _legalForms) {
    final f = form.toLowerCase();
    if (lower.startsWith(f) && (name.length == f.length || _formBoundary.hasMatch(name[f.length]))) {
      return name.substring(f.length).trim();
    }
  }
  return name;
}

/// Позиция закрывающей кавычки для имени, начатого кавычкой: первая кавычка, за которой конец строки или
/// принадлежность; иначе последняя. Так переживаются лишняя кавычка в конце и вложенные кавычки. -1 — кавычек нет.
int _closingQuote(String text) {
  final candidates = [for (var i = 1; i < text.length; i++) if (_closeQuotes.contains(text[i])) i];
  if (candidates.isEmpty) {
    return -1;
  }
  for (final i in candidates) {
    final tail = text.substring(i + 1).trim();
    if (tail.isEmpty || _affiliationTail.hasMatch(tail)) {
      return i;
    }
  }
  return candidates.last;
}
