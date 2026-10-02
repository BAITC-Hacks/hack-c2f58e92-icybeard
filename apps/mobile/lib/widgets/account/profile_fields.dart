// Поля листа «Личные данные»: телефон Казахстана и часовые пояса (веб `lib/validation.ts`). Чистые функции — под
// юнит-тесты.

/// Цифры номера без оформления; ведущая 8 у одиннадцати цифр — 7.
String phoneDigits(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length == 11 && digits.startsWith('8') ? '7${digits.substring(1)}' : digits;
}

/// Телефон Казахстана: +7 и 10 цифр (мобильный или городской).
bool isKzPhone(String value) {
  final digits = phoneDigits(value);
  return digits.length == 11 && digits.startsWith('7');
}

/// Как телефон уходит в `PUT /me/profile`: `+` и цифры; пустое поле — null (номер стирается).
String? normalizedPhone(String value) => value.trim().isEmpty ? null : '+${phoneDigits(value)}';

/// «+7 701 000 00 00» из одиннадцати цифр; иначе — как введено.
String formatKzPhone(String value) {
  final d = phoneDigits(value);
  if (d.length != 11) {
    return value;
  }
  return '+${d[0]} ${d.substring(1, 4)} ${d.substring(4, 7)} ${d.substring(7, 9)} ${d.substring(9, 11)}';
}

/// Часовые пояса Казахстана, как в вебе (с 01.03.2024 вся страна — UTC+5).
const kzTimeZones = ['Asia/Almaty', 'Asia/Qostanay', 'Asia/Qyzylorda', 'Asia/Aqtobe', 'Asia/Aqtau', 'Asia/Atyrau', 'Asia/Oral'];

/// Город пояса без «Asia/»; чужой пояс — как есть.
String timeZoneCity(String zone) => zone.startsWith('Asia/') ? zone.substring(5) : zone;
