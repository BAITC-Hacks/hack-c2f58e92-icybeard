/// Форматтеры чисел и дат для экранов. Даты API — ISO `yyyy-MM-dd` или timestamp; показываем `dd.MM.yyyy`
/// без зависимости от локальных данных intl (шаблон одинаков для ru и kk).
String days(double? value) => value == null ? '—' : value.round().toString();

String pct(double? value) => value == null ? '—' : '${(value * 100).round()} %';

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

/// ИИН показывается только маской: последние четыре цифры.
String maskIin(String? iin) => iin == null || iin.length < 4 ? '—' : '•••••••• ${iin.substring(iin.length - 4)}';

String _two(int value) => value.toString().padLeft(2, '0');
