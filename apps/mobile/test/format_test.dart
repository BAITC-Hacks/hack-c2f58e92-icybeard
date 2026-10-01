import 'package:darumen/l10n/strings.dart';
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

    // Векторы веба (apps/web/src/__tests__/format.test.ts) — одно правило в обоих клиентах.
    const webVectors = [
      ('Товарищество с ограниченной ответственностью "Достар Мед"', 'Достар Мед'),
      (
        'Коммунальное государственное предприятие на праве хозяйственного ведения "Алматинский онкологический центр" Управления общественного здравоохранения города Алматы',
        'Алматинский онкологический центр',
      ),
      (
        'Товарищество с ограниченной ответственностью "Казахский ордена "Знак Почета" научно-исследовательский институт глазных болезней"',
        'Казахский научно-исследовательский институт глазных болезней',
      ),
      (
        'Государственное учреждение "Региональный военный госпиталь с поликлиникой Комитета национальной безопасности Республики Казахстан в городе Алматы"',
        'Региональный военный госпиталь с поликлиникой Комитета национальной безопасности Республики Казахстан в городе Алматы',
      ),
      ('республиканское государственное предприятие на праве хозяйственного ведения "Госпиталь ветеранов" Министерства здравоохранения Республики Казахстан', 'Госпиталь ветеранов'),
      ('ГКППХВ "Бейнеуская центральная районная больница" Управления здравоохранения Мангистауской области', 'Бейнеуская центральная районная больница'),
      ('ТОО "Медицинский центр ХАК"', 'Медицинский центр ХАК'),
      ('АО "Научный центр педиатрии"', 'Научный центр педиатрии'),
      (
        'Государственное коммунальное предприятие "Городская клиническая больница №1" на праве хозяйственного ведения Управления здравоохранения города Алматы',
        'Городская клиническая больница №1',
      ),
      (
        'Коммунальное государственное предприятие на праве хозяйственного ведения "Городская клиническая больница №4" Управления общественного здравоохранения города Алматы"',
        'Городская клиническая больница №4',
      ),
      (
        'Коммунальное государственное предприятие на праве хозяйственного ведения "Реабилитационный центр "Алау" Управления здравоохранения города Алматы',
        'Реабилитационный центр "Алау"',
      ),
      ('Акционерное общество "Лечебно-оздоровительный комплекс "Ок-Жетпес"', 'Лечебно-оздоровительный комплекс "Ок-Жетпес"'),
      ('Товарищество с ограниченной ответственностью «MEDITERRA» (МЕДИТЕРРА)', 'MEDITERRA'),
      ('Товарищество с ограниченной ответственностью "Burc Medical" (Бурч Медикал)', 'Burc Medical'),
      ('Учреждение Больница №3', 'Больница №3'),
      ('Достар Мед', 'Достар Мед'),
      ('', ''),
    ];
    for (final (full, short) in webVectors) {
      test('web vector: $full → $short', () => expect(shortOrgName(full), short));
    }

    test('null gives an empty string, as on the web', () => expect(shortOrgName(null), ''));

    test('strips «на праве …» left after the legal form and the казённое forms', () {
      expect(shortOrgName('Государственное коммунальное предприятие на праве оперативного управления "Центр крови"'), 'Центр крови');
      expect(shortOrgName('Коммунальное государственное казённое предприятие "Детский сад"'), 'Детский сад');
      expect(shortOrgName('на праве хозяйственного ведения "Центр крови"'), 'Центр крови');
    });

    test('keeps the Kazakh legal forms of the mobile dictionary', () {
      expect(shortOrgName('Жауапкершілігі шектеулі серіктестік «Достар Мед»'), 'Достар Мед');
      expect(shortOrgName('ШЖҚ КМК "Қалалық емхана №5"'), 'Қалалық емхана №5');
      expect(shortOrgName('КеАҚ «Астана медицина университеті»'), 'Астана медицина университеті');
      expect(shortOrgName('Мемлекеттік мекеме "Аурухана"'), 'Аурухана');
      expect(shortOrgName('Ммм клиника'), 'Ммм клиника', reason: 'ММ — только целым словом');
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

  group('route date', () {
    test('takes the calendar date of the ISO value without a time-zone shift (as lib/route.ts on the web)', () {
      expect(routeDate('2025-03-31'), '31.03.2025');
      expect(routeDate('2025-03-31T23:30:00+00:00'), '31.03.2025', reason: 'дата из значения, не из часового пояса устройства');
      expect(routeDate('2025-04-01T01:30:00+05:00'), '01.04.2025');
    });

    test('dash for empty, unknown formats as they are', () {
      expect(routeDate(null), '—');
      expect(routeDate(''), '—');
      expect(routeDate('31.03.2025'), '31.03.2025');
    });
  });

  group('days and the estimate prefix', () {
    test('approxDays prefixes a modelled day value with «≈», a dash without a value', () {
      expect(approxDays(47.4), '≈ 47');
      expect(approxDays(0), '≈ 0');
      expect(approxDays(null), '—');
    });

    test('daysWithUnit uses the short unit in both languages', () {
      expect(daysWithUnit(21, S.of('ru')), '21 дн.');
      expect(daysWithUnit(20.6, S.of('kk')), '21 күн');
      expect(daysWithUnit(null, S.of('ru')), '—');
    });

    test('benchmark lines use «дн.», never «дней»', () {
      expect(S.of('ru').benchmarkShort('21'), isNot(contains('дней')));
      expect(S.of('ru').benchmarkSentence('21'), 'Ориентир Минздрава РК — ждать не больше 21 дн.');
      expect(S.of('kk').benchmarkSentence('21'), 'ҚР Денсаулық сақтау министрлігінің бағдары — 21 күннен ұзақ күтпеу');
    });
  });

  group('rounded difference', () {
    test('subtracts the rounded values the user sees (≈ 4 and ≈ 2 → 2)', () {
      expect(roundedDaysDiff(4.4, 2.4), 2, reason: 'round(4.4) − round(2.4) = 4 − 2');
      expect(roundedDaysDiff(4.6, 2.4), 3);
      expect(roundedDaysDiff(4.4, 3.6), 0, reason: 'на экране ≈ 4 и ≈ 4 — «как в вашей больнице», хотя разность 0.8');
      expect(roundedDaysDiff(2.4, 4.4), -2, reason: 'там дольше');
    });

    test('null when either value is missing', () {
      expect(roundedDaysDiff(null, 2), isNull);
      expect(roundedDaysDiff(2, null), isNull);
    });
  });

  group('refusal risk in words', () {
    test('three bands around the national 11 % with the web thresholds (>= 0.165 above, <= 0.055 below)', () {
      expect(refusalLevel(0.165), RefusalLevel.above);
      expect(refusalLevel(0.4), RefusalLevel.above);
      expect(refusalLevel(0.1649), RefusalLevel.average);
      expect(refusalLevel(0.11), RefusalLevel.average);
      expect(refusalLevel(0.0551), RefusalLevel.average);
      expect(refusalLevel(0.055), RefusalLevel.below);
      expect(refusalLevel(0), RefusalLevel.below);
      expect(refusalLevel(null), isNull);
      expect(refusalLevel(double.nan), isNull);
    });

    test('words in both languages as in the web dictionary, a dash without a value', () {
      final ru = S.of('ru');
      final kk = S.of('kk');
      expect(refusalWords(ru, 0.2), 'выше среднего');
      expect(refusalWords(ru, 0.1), 'около среднего');
      expect(refusalWords(ru, 0.01), 'ниже среднего');
      expect(refusalWords(kk, 0.2), 'орташадан жоғары');
      expect(refusalWords(kk, 0.1), 'орташа шамада');
      expect(refusalWords(kk, 0.01), 'орташадан төмен');
      expect(refusalWords(ru, null), '—');
    });
  });

  group('capitalizeFirst', () {
    test('upper-cases only the first letter, Kazakh letters included', () {
      expect(capitalizeFirst('риск отказа'), 'Риск отказа');
      expect(capitalizeFirst('әлі күтуде'), 'Әлі күтуде');
      expect(capitalizeFirst('Уже с заглавной'), 'Уже с заглавной');
      expect(capitalizeFirst('> 30 дней'), '> 30 дней');
      expect(capitalizeFirst(''), '');
      expect(capitalizeFirst('ИИН'), 'ИИН', reason: 'остальные буквы не трогаем');
    });
  });
}
