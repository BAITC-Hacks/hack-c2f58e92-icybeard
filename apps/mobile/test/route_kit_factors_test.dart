import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/widgets/route/forecast_factors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Из чего сложился прогноз» (useForecastFactors.ts): подписи по коду признака, значение из текста модели, вклад
/// целыми днями «+N дн. к ожиданию» / «−N дн. от ожидания» / «почти не влияет», пояснение по знаку.
const factorNames = [
  'mo_code',
  'region_kato',
  'profile_code',
  'icd_chapter',
  'icd_block',
  'referral_purpose',
  'finance_source',
  'territorial_type',
  'mo_size_bucket',
  'mo_type',
  'queue_age_p50',
  'queue_age_p90',
  'throughput_per_day',
  'refusal_rate_4w',
  'wait_p50_4w',
  'wait_p90_4w',
  'dow',
  'week_of_year',
];
const hintKeys = [
  'mo_code',
  'same_mo_no',
  'same_mo_yes',
  'queue_len',
  'profile_code',
  'queue_age_p50',
  'throughput_per_day',
  'refusal_rate_4w',
  'icd_chapter',
  'icd_block',
  'referral_purpose',
  'territorial_type',
  'wait_p50_4w',
];

final ru = S.of('ru');
final kk = S.of('kk');
final webRu = File('../web/src/i18n/ru.ts').readAsStringSync();
final webKk = File('../web/src/i18n/kk.ts').readAsStringSync();

void expectWeb(String text, {required bool kazakh}) =>
    expect(kazakh ? webKk : webRu, contains("'$text'"), reason: '«$text» должна быть дословно в ${kazakh ? 'kk' : 'ru'}.ts');

Widget host(Widget child, {String locale = 'ru', double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(360, 800)),
        // 360 dp телефона минус поля страницы и карточки (по 16 с каждой стороны)
        child: Scaffold(body: Center(child: SizedBox(width: 296, child: SingleChildScrollView(child: child)))),
      ),
    );

/// Факторы из настоящего ответа `GET /route/{ref}` (test/fixtures/api/route-doctor.json → doctor.shap.factors).
List<Factor> fixtureFactors() {
  final json = jsonDecode(File('test/fixtures/api/route-doctor.json').readAsStringSync()) as Map<String, dynamic>;
  final shap = (json['doctor'] as Map<String, dynamic>)['shap'] as Map<String, dynamic>;
  return Explanation.fromJson(shap).factors;
}

void main() {
  group('словарь факторов', () {
    test('18 подписей route.factor.* и 13 пар пояснений route.factorHint.* — дословно, RU и KK', () {
      for (final dict in [ru, kk]) {
        final kazakh = dict == kk;
        for (final name in factorNames) {
          expectWeb(dict.factorLabel(name)!, kazakh: kazakh);
        }
        for (final key in hintKeys) {
          expectWeb(dict.factorHint(key, plus: true)!, kazakh: kazakh);
          expectWeb(dict.factorHint(key, plus: false)!, kazakh: kazakh);
          expect(dict.factorHint(key, plus: true), isNot(dict.factorHint(key, plus: false)));
        }
        expectWeb(dict.factorSameMo(true), kazakh: kazakh);
        expectWeb(dict.factorSameMo(false), kazakh: kazakh);
        expectWeb(dict.factorQueueLength('{n}'), kazakh: kazakh);
        expectWeb(dict.factorProfileNamed('{name}'), kazakh: kazakh);
        expectWeb(dict.factorAddsDays(9876).replaceAll('9876', '{n}'), kazakh: kazakh);
        expectWeb(dict.factorTakesDays(9876).replaceAll('9876', '{n}'), kazakh: kazakh);
        expectWeb(dict.factorNoEffect, kazakh: kazakh);
        expectWeb(dict.factorsTitle, kazakh: kazakh);
        expectWeb(dict.factorsLead, kazakh: kazakh);
        expectWeb(dict.factorsNote, kazakh: kazakh);
      }
    });

    test('незнакомый признак и пояснение — null: подпись тогда берётся из текста модели', () {
      expect(ru.factorLabel('weather'), isNull);
      expect(ru.factorLabel('same_mo'), isNull, reason: 'same_mo подписывается по значению — factorSameMo');
      expect(ru.factorHint('dow', plus: true), isNull);
      expect(ru.factorAddsDays(26), '+26 дн. к ожиданию');
      expect(ru.factorTakesDays(3), '−3 дн. от ожидания', reason: 'минус — U+2212, как в вебе');
      expect(kk.factorAddsDays(26), 'күтуге +26 күн');
    });
  });

  group('forecastFactors — чистое сопоставление', () {
    test('настоящие факторы модели: подписи, целые дни, направление и пояснение по знаку', () {
      final rows = forecastFactors(fixtureFactors(), ru);
      expect([for (final r in rows) r.name], ['mo_code', 'same_mo', 'queue_age_p50', 'icd_block']);
      expect([for (final r in rows) r.label], ['Эта больница', 'Направляет другая организация', 'Сколько уже ждут в очереди', 'Группа диагноза']);
      expect([for (final r in rows) r.effect], ['−10 дн. от ожидания', '+8 дн. к ожиданию', '+7 дн. к ожиданию', '−4 дн. от ожидания']);
      expect([for (final r in rows) r.direction], [FactorDirection.minus, FactorDirection.plus, FactorDirection.plus, FactorDirection.minus]);
      expect(rows[0].hint, ru.factorHint('mo_code', plus: false));
      expect(rows[1].hint, ru.factorHint('same_mo_no', plus: true));
      expect(rows[3].hint, ru.factorHint('icd_block', plus: false));
    });

    test('same_mo по значению True/1 — своя больница; очередь и профиль подставляют значение', () {
      final rows = forecastFactors(
        const [
          Factor(name: 'same_mo', contribution: -2.4, text: 'направление внутри своей организации: True (−2.4 дн.)'),
          Factor(name: 'same_mo', contribution: 1.2, text: 'направление внутри своей организации: 1 (+1.2 дн.)'),
          Factor(name: 'queue_len', contribution: 9.0, text: 'очередь в организации: 133 (+9.0 дн.)'),
          Factor(name: 'profile_code', contribution: 3.3, text: 'профиль койки: 121 (+3.3 дн.)'),
        ],
        ru,
        profileName: 'Хирургические для взрослых',
      );
      expect(rows[0].label, 'Направляет эта же больница');
      expect(rows[0].hint, ru.factorHint('same_mo_yes', plus: false));
      expect(rows[1].label, 'Направляет эта же больница');
      expect(rows[2].label, 'Длина очереди: 133');
      expect(rows[2].hint, ru.factorHint('queue_len', plus: true));
      expect(rows[3].label, 'Профиль койки: Хирургические для взрослых');
    });

    test('без значения и без названия профиля — подпись словаря или текст модели без скобок', () {
      final rows = forecastFactors(
        const [
          Factor(name: 'profile_code', contribution: 3.3, text: 'профиль койки: 121 (+3.3 дн.)'),
          Factor(name: 'queue_len', contribution: 2, text: 'очередь (+2.0 дн.)'),
          Factor(name: 'weather', contribution: -1.6, text: 'погода: дождь (−1.6 дн.)'),
        ],
        ru,
      );
      expect(rows[0].label, 'Профиль койки');
      expect(rows[1].label, 'очередь', reason: 'для queue_len без числа в вебе нет подписи — остаётся текст модели');
      expect(rows[2].label, 'погода: дождь');
      expect(rows[2].hint, '', reason: 'пояснения к незнакомому признаку нет');
    });

    test('меньше половины дня — «почти не влияет», без пояснения; половина округляется вверх', () {
      final rows = forecastFactors(
        const [
          Factor(name: 'mo_code', contribution: 0.4, text: 'организация: 224E (+0.4 дн.)'),
          Factor(name: 'mo_code', contribution: -0.49, text: 'организация: 224E (−0.5 дн.)'),
          Factor(name: 'mo_code', contribution: 2.5, text: 'организация: 224E (+2.5 дн.)'),
          Factor(name: 'mo_code', contribution: -2.5, text: 'организация: 224E (−2.5 дн.)'),
        ],
        kk,
      );
      expect(rows[0].direction, FactorDirection.zero);
      expect(rows[0].effect, 'әсері шамалы');
      expect(rows[0].hint, '');
      expect(rows[1].direction, FactorDirection.zero);
      expect(rows[2].effect, 'күтуге +3 күн');
      expect(rows[3].effect, 'күтуден −3 күн');
      expect(rows[3].label, 'Осы аурухана');
    });

    test('пустой список — пустой результат; вход не меняется, copyWith даёт новую строку', () {
      expect(forecastFactors(const [], ru), isEmpty);
      final input = [const Factor(name: 'dow', contribution: 1.1, text: 'день недели: 2 (+1.1 дн.)')];
      final rows = forecastFactors(input, ru);
      expect(input.single.text, 'день недели: 2 (+1.1 дн.)');
      final renamed = rows.single.copyWith(label: 'Направляющая не указана', hint: 'Укажите направляющую');
      expect(renamed.label, 'Направляющая не указана');
      expect(renamed.hint, 'Укажите направляющую');
      expect(renamed.effect, rows.single.effect);
      expect(rows.single.label, 'День недели направления');
    });
  });

  group('ForecastFactorList', () {
    testWidgets('строки: подпись, пояснение, вклад справа; плюс — danger, минус — ok, ноль — приглушённый', (tester) async {
      final rows = forecastFactors(
        [...fixtureFactors(), const Factor(name: 'dow', contribution: 0.2, text: 'день недели: 2 (+0.2 дн.)')],
        ru,
      );
      await tester.pumpWidget(host(ForecastFactorList(items: rows, lead: ru.factorsLead, note: ru.factorsNote)));
      expect(find.text(ru.factorsLead), findsOneWidget);
      expect(find.text(ru.factorsNote), findsOneWidget);
      expect(find.text('Эта больница'), findsOneWidget);
      expect(find.text(ru.factorHint('mo_code', plus: false)!), findsOneWidget);
      final tones = AppTones.from(ColorTokens.light);
      expect(tester.widget<Text>(find.text('+8 дн. к ожиданию')).style?.color, tones.danger.fg);
      expect(tester.widget<Text>(find.text('−10 дн. от ожидания')).style?.color, tones.ok.fg);
      expect(tester.widget<Text>(find.text('почти не влияет')).style?.color, ColorTokens.light.muted);
    });

    testWidgets('без строк — ничего не рисует', (tester) async {
      await tester.pumpWidget(host(ForecastFactorList(items: const [], lead: ru.factorsLead)));
      expect(find.text(ru.factorsLead), findsNothing);
    });

    for (final locale in ['ru', 'kk']) {
      testWidgets('без переполнения на 360 dp при крупном шрифте 1.3 ($locale)', (tester) async {
        final dict = S.of(locale);
        final rows = forecastFactors(
          [
            ...fixtureFactors(),
            const Factor(name: 'throughput_per_day', contribution: 126.4, text: 'пропускная способность: 3 (+126.4 дн.)'),
          ],
          dict,
          profileName: 'Хирургические для взрослых (кардиохирургия)',
        );
        await tester.pumpWidget(host(ForecastFactorList(items: rows, lead: dict.factorsLead, note: dict.factorsNote), locale: locale, textScale: 1.3));
        expect(tester.takeException(), isNull);
        expect(find.text(dict.factorAddsDays(126)), findsOneWidget);
      });
    }
  });
}
