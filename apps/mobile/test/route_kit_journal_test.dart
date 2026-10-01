import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/widgets/route/route_journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Лента журнала маршрута (RouteFeed.vue): точка 30 с тоном по виду, заголовок по голосу, «дата, время · кто»,
/// назначенная дата и плашка с причиной или комментарием. Порядок — серверный (свежие первыми).
Widget host(Widget child, {String locale = 'ru', double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(360, 800)),
        child: Scaffold(body: Center(child: SizedBox(width: 296, child: SingleChildScrollView(child: child)))),
      ),
    );

const c = ColorTokens.light;
final tones = AppTones.from(c);

/// Журнал настоящего `GET /route/me` (test/fixtures/api/route-me.json): предложение перевода, просьбы гражданина,
/// решение «оставить» и подтверждение ожидания — свежие первыми.
List<RouteJournalEntry> fixtureJournal() {
  final json = jsonDecode(File('test/fixtures/api/route-me.json').readAsStringSync()) as Map<String, dynamic>;
  return PatientRoute.fromJson(json).journal;
}

const longOrg = 'Товарищество с ограниченной ответственностью "Достар Мед"';

/// Запись журнала со временем без часового пояса — разбирается как местное, время в строке не зависит от машины.
RouteJournalEntry entry(String kind, {String role = 'doctor', String? moName = longOrg, String? reason, String? plannedAt, bool severe = false}) =>
    RouteJournalEntry(
      id: 'id-$kind',
      at: '2026-09-25T19:26:38',
      kind: kind,
      role: role,
      moCode: moName == null ? null : '22GN',
      moName: moName,
      reason: reason,
      plannedAt: plannedAt,
      severe: severe,
    );

Color? dotColor(WidgetTester tester, String kind) {
  final dot = find.descendant(of: find.byKey(ValueKey('journal-dot-$kind')), matching: find.byType(Container)).first;
  return (tester.widget<Container>(dot).decoration! as BoxDecoration).color;
}

void main() {
  group('тон, значок и время записи', () {
    test('тон точки по виду: свои записи гражданина — signal, отказ/отмена/неявка — stop, решения «за» — keep, остальное — redirect', () {
      for (final kind in ['request', 'prefer_current', 'still_waiting', 'withdraw', 'treated_elsewhere', 'consent_accepted', 'consent_declined']) {
        expect(journalToneOf(kind), JournalTone.signal, reason: kind);
      }
      for (final kind in ['reject', 'cancel', 'no_show']) {
        expect(journalToneOf(kind), JournalTone.stop, reason: kind);
      }
      for (final kind in ['keep', 'confirm', 'admit', 'discharge']) {
        expect(journalToneOf(kind), JournalTone.keep, reason: kind);
      }
      for (final kind in ['redirect', 'reschedule', 'close', 'escalate']) {
        expect(journalToneOf(kind), JournalTone.redirect, reason: kind);
      }
    });

    test('значки как в вебе: перевод — стрелки, календарь — подтверждение и перенос, флаг — снятие, прочее — комментарий', () {
      expect(journalIconOf('redirect'), Icons.swap_horiz);
      expect(journalIconOf('keep'), Icons.check);
      expect(journalIconOf('confirm'), Icons.event);
      expect(journalIconOf('reschedule'), Icons.event);
      expect(journalIconOf('admit'), Icons.apartment);
      expect(journalIconOf('discharge'), Icons.logout);
      expect(journalIconOf('reject'), Icons.close);
      expect(journalIconOf('close'), Icons.flag_outlined);
      expect(journalIconOf('consent_accepted'), Icons.thumb_up_outlined);
      expect(journalIconOf('consent_declined'), Icons.thumb_down_outlined);
      expect(journalIconOf('still_waiting'), Icons.chat_bubble_outline);
    });

    test('время записи — «дд.мм.гггг, чч:мм» по часам устройства; пусто — «—», мусор — как есть', () {
      expect(journalMoment('2026-09-25T19:26:38'), '25.09.2026, 19:26');
      expect(journalMoment('2026-02-03T07:05:00'), '03.02.2026, 07:05');
      final utc = DateTime.parse('2026-09-25T19:26:38.487527+00:00').toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      expect(journalMoment('2026-09-25T19:26:38.487527+00:00'), '${two(utc.day)}.${two(utc.month)}.${utc.year}, ${two(utc.hour)}:${two(utc.minute)}');
      expect(journalMoment(''), '—');
      expect(journalMoment('вчера'), 'вчера');
    });
  });

  group('RouteJournal', () {
    testWidgets('гражданину: второе лицо, короткие имена, «кто» — «вы» или роль, подпись плашки по автору', (tester) async {
      await tester.pumpWidget(host(RouteJournal(entries: fixtureJournal(), voice: RouteVoice.citizen)));
      expect(find.text('Врач предложил перевод: Достар Мед'), findsOneWidget);
      expect(find.text('Вы попросили рассмотреть: Достар Мед'), findsOneWidget);
      expect(find.text('Врач оставил вас в вашей больнице'), findsOneWidget);
      expect(find.text('Вы подтвердили, что ждёте'), findsOneWidget);
      expect(find.textContaining('· вы'), findsNWidgets(3));
      expect(find.textContaining('· врач'), findsNWidgets(3));
      expect(find.text('Ваш комментарий'), findsNWidgets(2));
      expect(find.text('Причина'), findsNWidgets(3));
      expect(find.text('zhakyn'), findsOneWidget);
      expect(find.text('профиль требует именно этой клиники'), findsOneWidget);
      expect(find.text(S.of('ru').routeSevereMark), findsNothing);
    });

    testWidgets('порядок — как пришёл с сервера, без пересортировки', (tester) async {
      final entries = [entry('confirm', plannedAt: '2026-10-05'), entry('still_waiting', role: 'citizen', moName: null), entry('redirect')];
      await tester.pumpWidget(host(RouteJournal(entries: entries, voice: RouteVoice.citizen)));
      final confirm = tester.getTopLeft(find.text('Достар Мед: приём подтверждён')).dy;
      final waiting = tester.getTopLeft(find.text('Вы подтвердили, что ждёте')).dy;
      final redirect = tester.getTopLeft(find.text('Врач предложил перевод: Достар Мед')).dy;
      expect(confirm < waiting && waiting < redirect, isTrue);
      expect(find.text('Дата госпитализации: 05.10.2026'), findsOneWidget);
    });

    testWidgets('персоналу: третье лицо, «пациент», «Комментарий пациента», отметка тяжёлого случая и эпикриз', (tester) async {
      final entries = [
        entry('discharge', role: 'org_admin', reason: 'Выписан в удовлетворительном состоянии'),
        entry('redirect', severe: true, reason: 'там раньше дата'),
        entry('request', role: 'citizen', reason: 'живу рядом'),
      ];
      await tester.pumpWidget(host(RouteJournal(entries: entries, voice: RouteVoice.staff)));
      expect(find.text('Выписан: Достар Мед'), findsOneWidget);
      expect(find.text('Предложен перевод: Достар Мед'), findsOneWidget);
      expect(find.text('Пациент просит рассмотреть: Достар Мед'), findsOneWidget);
      expect(find.textContaining('· админ. организации'), findsOneWidget);
      expect(find.textContaining('· пациент'), findsOneWidget);
      expect(find.textContaining('тяжёлый случай'), findsOneWidget);
      expect(find.text('Комментарий пациента'), findsOneWidget);
      expect(find.text('Выписан в удовлетворительном состоянии'), findsOneWidget);
    });

    testWidgets('гражданину отметка тяжёлого случая не показывается, даже если пришла', (tester) async {
      await tester.pumpWidget(host(RouteJournal(entries: [entry('redirect', severe: true)], voice: RouteVoice.citizen)));
      expect(find.textContaining('тяжёлый случай'), findsNothing);
    });

    testWidgets('точка: signal — warn-пара, keep — ok, stop — нейтральная, redirect — accent-subtle', (tester) async {
      final entries = [entry('request', role: 'citizen'), entry('admit'), entry('cancel', moName: null), entry('redirect')];
      await tester.pumpWidget(host(RouteJournal(entries: entries, voice: RouteVoice.citizen)));
      expect(dotColor(tester, 'request'), tones.warn.bg);
      expect(dotColor(tester, 'admit'), tones.ok.bg);
      expect(dotColor(tester, 'cancel'), c.neutralSoft);
      expect(dotColor(tester, 'redirect'), c.accentSubtle);
      expect(tester.getSize(find.byKey(const ValueKey('journal-dot-admit'))), const Size.square(AppSizes.feedDot));
    });

    testWidgets('пустая лента — «Решений пока нет.»', (tester) async {
      await tester.pumpWidget(host(const RouteJournal(entries: [], voice: RouteVoice.citizen), locale: 'kk'));
      expect(find.text('Шешімдер әлі жоқ.'), findsOneWidget);
    });

    testWidgets('тап по заголовку с длинным юридическим именем открывает полное название', (tester) async {
      await tester.pumpWidget(host(RouteJournal(entries: [entry('confirm')], voice: RouteVoice.citizen)));
      await tester.tap(find.text('Достар Мед: приём подтверждён'));
      await tester.pumpAndSettle();
      expect(find.text(longOrg), findsOneWidget);
    });

    for (final locale in ['ru', 'kk']) {
      testWidgets('без переполнения на 360 dp при крупном шрифте 1.3 ($locale)', (tester) async {
        final entries = [
          ...fixtureJournal(),
          entry('reschedule', role: 'org_admin', plannedAt: '2026-10-05', reason: 'ozhidanie_koroche_profil_sovpadaet_dlinnoe_slovo_bez_probelov'),
          entry('redirect', severe: true, reason: 'там раньше дата'),
        ];
        for (final voice in RouteVoice.values) {
          await tester.pumpWidget(host(RouteJournal(entries: entries, voice: voice), locale: locale, textScale: 1.3));
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
