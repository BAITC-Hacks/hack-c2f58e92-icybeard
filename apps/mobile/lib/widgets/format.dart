/// Форматтеры чисел, дат и имён для экранов. Даты API — ISO `yyyy-MM-dd` или timestamp; показываем `dd.MM.yyyy`
/// без зависимости от локальных данных intl (шаблон одинаков для ru и kk).
String days(double? value) => value == null ? '—' : value.round().toString();

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

/// `dd.MM` — под точками степпера и в строках «дата назначена 31.03».
String dayMonth(String? iso) {
  final full = dateShort(iso);
  return full.length == 10 ? full.substring(0, 5) : full;
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

/// Только время `HH:mm` — для строк журнала, сгруппированных по дням.
String timeShort(String? iso) {
  final parsed = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return parsed == null ? '—' : '${_two(parsed.hour)}:${_two(parsed.minute)}';
}

/// Локальная дата события (без времени) — ключ группировки «Сегодня · Вчера · 22 сентября».
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

/// Организационно-правовые формы, которые убираются из начала юридического имени (регистр не важен). Длинные —
/// первыми, чтобы «Государственное учреждение» не срезалось до «Учреждение». Казахские формы — на случай
/// локализованного справочника.
const _legalForms = [
  'Товарищество с ограниченной ответственностью',
  'Коммунальное государственное предприятие на праве хозяйственного ведения',
  'Государственное коммунальное предприятие на праве хозяйственного ведения',
  'Республиканское государственное предприятие на праве хозяйственного ведения',
  'Государственное коммунальное казённое предприятие',
  'Государственное коммунальное казенное предприятие',
  'Коммунальное государственное предприятие',
  'Государственное коммунальное предприятие',
  'Республиканское государственное предприятие',
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
  'Жауапкершілігі шектеулі серіктестік',
  'Шаруашылық жүргізу құқығындағы коммуналдық мемлекеттік кәсіпорын',
  'Шаруашылық жүргізу құқығындағы республикалық мемлекеттік кәсіпорын',
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

final _legalFormPattern = RegExp(
  '^(?:${_legalForms.map(RegExp.escape).join('|')})(?=\\s|["«]|\$)',
  caseSensitive: false,
  unicode: true,
);

/// Фрагменты «ордена "Знак Почета"» внутри имени.
final _orderPattern = RegExp(r'\s*ордена\s+["«][^"»]*["»]', caseSensitive: false, unicode: true);

final _spaces = RegExp(r'\s+');

/// Короткое имя организации для списков, карточек и уведомлений: без организационно-правовой формы и
/// «хвоста» учредителя. `ТОО "Достар Мед"` → `Достар Мед`; `КГП на ПХВ "Алматинский онкологический центр"
/// Управления общественного здравоохранения города Алматы` → `Алматинский онкологический центр`. Полное
/// юридическое имя остаётся для деталей (подстрока или лист по тапу). Одинаковые правила в вебе.
String shortOrgName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  final rest = trimmed.replaceFirst(_legalFormPattern, '').trim();
  final quoted = _outerQuoted(rest);
  final core = (quoted ?? rest).replaceAll(_orderPattern, ' ').replaceAll(_spaces, ' ').trim();
  return core.isEmpty ? trimmed : core;
}

/// Текст между первой кавычкой и парной ей закрывающей; null, если остаток не начинается с кавычки.
/// Прямая кавычка `"` считается открывающей после начала строки, пробела или скобки, иначе — закрывающей.
String? _outerQuoted(String text) {
  if (text.isEmpty || !(text[0] == '"' || text[0] == '«')) {
    return null;
  }
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    final opening = ch == '«' || (ch == '"' && (i == 0 || text[i - 1] == ' ' || text[i - 1] == '('));
    final closing = ch == '»' || (ch == '"' && !opening);
    if (opening) {
      depth++;
    } else if (closing) {
      depth--;
      if (depth == 0) {
        return text.substring(1, i);
      }
    }
  }
  final last = text.lastIndexOf(RegExp('["»]'));
  return last > 0 ? text.substring(1, last) : text.substring(1);
}
