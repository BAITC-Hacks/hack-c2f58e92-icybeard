import 'package:darumen/widgets/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortOrgName', () {
    test('drops the legal form and keeps the quoted name', () {
      expect(shortOrgName('Товарищество с ограниченной ответственностью "Достар Мед"'), 'Достар Мед');
      expect(shortOrgName('ТОО "Достар Мед"'), 'Достар Мед');
      expect(shortOrgName('Акционерное общество "Казахский научно-исследовательский институт онкологии и радиологии"'),
          'Казахский научно-исследовательский институт онкологии и радиологии');
      expect(shortOrgName('НАО «Медицинский университет Астана»'), 'Медицинский университет Астана');
    });

    test('cuts the founder tail after the closing quote', () {
      expect(
        shortOrgName('Коммунальное государственное предприятие на праве хозяйственного ведения "Алматинский онкологический центр" '
            'Управления общественного здравоохранения города Алматы'),
        'Алматинский онкологический центр',
      );
      expect(shortOrgName('КГП на ПХВ "Городской перинатальный центр" Управления общественного здравоохранения города Алматы'), 'Городской перинатальный центр');
    });

    test('removes nested «ордена …» fragments and keeps outer quotes paired', () {
      expect(
        shortOrgName('Товарищество с ограниченной ответственностью "Казахский ордена "Знак Почета" научно-исследовательский институт глазных болезней"'),
        'Казахский научно-исследовательский институт глазных болезней',
      );
    });

    test('keeps long names without a tail intact', () {
      expect(
        shortOrgName('Государственное учреждение "Региональный военный госпиталь с поликлиникой Комитета национальной безопасности '
            'Республики Казахстан в городе Алматы"'),
        'Региональный военный госпиталь с поликлиникой Комитета национальной безопасности Республики Казахстан в городе Алматы',
      );
    });

    test('is case-insensitive, tolerates missing quotes and never returns an empty string', () {
      expect(shortOrgName('тоо Достар Мед'), 'Достар Мед');
      expect(shortOrgName('Государственное учреждение Больница №5'), 'Больница №5');
      expect(shortOrgName('Гурьевская больница'), 'Гурьевская больница', reason: 'ГУ — только целым словом');
      expect(shortOrgName('Учреждение "Клиника"'), 'Клиника');
      expect(shortOrgName('ТОО ""'), 'ТОО ""');
      expect(shortOrgName('  '), '');
      expect(shortOrgName('ЖШС «Достар Мед»'), 'Достар Мед');
    });
  });

  group('formatters', () {
    test('mask the iin to the last four digits', () {
      expect(maskIin('000000004321'), '•••• 4321');
      expect(maskIin('12'), '—');
      expect(maskIin(null), '—');
    });

    test('render dates, day-month, time and thousands', () {
      expect(dateShort('2025-03-31'), '31.03.2025');
      expect(dayMonth('2025-03-31'), '31.03');
      expect(dayMonth(null), '—');
      expect(localDay('2025-03-31'), DateTime(2025, 3, 31));
      expect(localDay('bad'), isNull);
      expect(timeShort(null), '—');
      expect(thousands(11330078), '11 330 078');
      expect(thousands(999), '999');
      expect(days(20.7), '21');
      expect(pct(0.559), '56 %');
    });
  });
}
