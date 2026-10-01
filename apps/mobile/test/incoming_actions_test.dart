import 'dart:async';
import 'dart:convert';

import 'package:darumen/api/almaty_time.dart';
import 'package:darumen/api/models.dart';
import 'package:darumen/screens/incoming_referrals_screen.dart';
import 'package:darumen/state/session.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/app_shell.dart';
import 'package:darumen/widgets/count_badge.dart';
import 'package:darumen/widgets/format.dart';
import 'package:darumen/widgets/incoming/incoming_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'incoming_referrals_test.dart' show actionButton, apiDay, demoIncoming, inCard, incomingJson, receivingApi, senderName, tallNarrow, tallPhone;
import 'support/harness.dart';

/// Действия принимающей больницы: что уходит на сервер (тело, ключ идемпотентности), лист на каждое действие и
/// подтверждение перед «Госпитализирован» / «Не пришёл» (Q-13), успех → список и колокольчик перечитаны, тост; 409 и
/// 404 → сначала перечитать, затем текст сервера; 422 — под полем; сеть — «Сервер недоступен»; двойное нажатие — один
/// запрос; счётчик вкладки следует за действием.

Finder get submit => find.byKey(const ValueKey('incoming-sheet-submit'));
Finder get sheetText => find.byKey(const ValueKey('incoming-sheet-text'));
Finder get sheetDate => find.byKey(const ValueKey('incoming-sheet-date'));
Finder get askConfirm => find.byKey(const ValueKey('incoming-ask-confirm'));

bool enabled(WidgetTester tester, Finder button) => tester.widget<ButtonStyleButton>(button).enabled;

Map<String, dynamic> bodyOf(http.Request request) => jsonDecode(request.body) as Map<String, dynamic>;

/// Экран входящих врача 22GN над [receivingApi] и дополнительными ответами [extra].
Future<(Session, DemoBackend)> receiving(
  WidgetTester tester, {
  Map<String, Object?> extra = const {},
  String locale = 'ru',
  double textScale = 1,
  Size size = tallPhone,
}) async {
  final (session, backend) = await demoSession(DemoUser.doctor2, api: {...receivingApi(), ...extra});
  await pumpScreen(tester, session, const IncomingReferralsScreen(), size: size, locale: locale, textScale: textScale);
  return (session, backend);
}

Future<void> tapAction(WidgetTester tester, String id, String label) async {
  await tester.tap(actionButton(id, label));
  await pumpFrames(tester);
}

void main() {
  final today = almatyTodayString();

  group('sheets send exactly what the server expects', () {
    testWidgets('confirm: today (Almaty) by default, optional comment; body, a fresh key, list and bell reloaded, toast', (tester) async {
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-sev/confirm': recorded('c-1')});
      final bellBefore = backend.calls('GET', '/journal/notifications/bell').length;
      await tapAction(tester, 'd-sev', 'Подтвердить приём');
      expect(find.text('SYN-75-028B-381-03 · ${shortOrgName(senderName)}'), findsOneWidget);
      expect(find.text(routeDate(today)), findsOneWidget);
      expect(find.text('Не раньше сегодня и не позже чем через 30 дней'), findsOneWidget);
      expect(enabled(tester, submit), isTrue, reason: 'комментарий необязателен');

      await tester.enterText(sheetText, '  Палата 3  ');
      await tester.tap(submit);
      await pumpFrames(tester);

      final post = backend.calls('POST', '/journal/referrals/d-sev/confirm').single;
      expect(bodyOf(post), {'patientRef': 'SYN-75-028B-381-03', 'plannedAt': today, 'comment': 'Палата 3'});
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(backend.calls('GET', '/journal/referrals/incoming'), hasLength(2), reason: 'после успеха список перечитан');
      expect(backend.calls('GET', '/journal/notifications/bell').length, greaterThan(bellBefore), reason: 'и колокольчик — счётчик вкладки');
      expect(find.text('Приём подтверждён'), findsOneWidget);
      expect(submit, findsNothing, reason: 'лист закрыт');
    });

    testWidgets('confirm without a comment sends no comment key', (tester) async {
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-sev/confirm': recorded()});
      await tapAction(tester, 'd-sev', 'Подтвердить приём');
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(bodyOf(backend.calls('POST', '/journal/referrals/d-sev/confirm').single), {'patientRef': 'SYN-75-028B-381-03', 'plannedAt': today});
    });

    testWidgets('the date picker is limited to today … today + 30 by Almaty; a picked day goes out as yyyy-MM-dd', (tester) async {
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-sev/confirm': recorded()});
      await tapAction(tester, 'd-sev', 'Подтвердить приём');
      await tester.tap(sheetDate);
      await pumpFrames(tester);
      final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      final window = plannedDateWindow();
      List<int> ymd(DateTime d) => [d.year, d.month, d.day];
      expect(ymd(dialog.firstDate), ymd(window.start));
      expect(ymd(dialog.lastDate), ymd(window.end));

      final next = window.start.add(const Duration(days: 1));
      final target = next.month == window.start.month ? next : window.start;
      await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('${target.day}')).first);
      await tester.pump();
      final ok = MaterialLocalizations.of(tester.element(find.byType(DatePickerDialog))).okButtonLabel;
      await tester.tap(find.text(ok));
      await pumpFrames(tester);
      expect(find.text(routeDate(formatApiDate(target))), findsOneWidget);
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(bodyOf(backend.calls('POST', '/journal/referrals/d-sev/confirm').single)['plannedAt'], formatApiDate(target));
    });

    testWidgets('reject: the reason is required (spaces do not count); body {patientRef, reason}', (tester) async {
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-sev/reject': recorded()});
      await tapAction(tester, 'd-sev', 'Отказать');
      expect(find.text('Отказ в приёме'), findsOneWidget);
      expect(sheetDate, findsNothing);
      expect(enabled(tester, submit), isFalse);
      await tester.enterText(sheetText, '   ');
      await tester.pump();
      expect(enabled(tester, submit), isFalse);
      await tester.enterText(sheetText, ' Нет свободных коек ');
      await tester.pump();
      expect(enabled(tester, submit), isTrue);
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(bodyOf(backend.calls('POST', '/journal/referrals/d-sev/reject').single), {'patientRef': 'SYN-75-028B-381-03', 'reason': 'Нет свободных коек'});
      expect(find.text('Отказ записан'), findsOneWidget);
    });

    testWidgets('reschedule: prefilled with the current date, reason required; body {patientRef, plannedAt, reason}', (tester) async {
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-sched/reschedule': recorded()});
      await tapAction(tester, 'd-sched', 'Перенести');
      expect(find.text('Перенос даты'), findsOneWidget);
      expect(find.text(routeDate(apiDay(2))), findsOneWidget);
      expect(enabled(tester, submit), isFalse);
      await tester.enterText(sheetText, 'Пациент попросил позже');
      await tester.pump();
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(bodyOf(backend.calls('POST', '/journal/referrals/d-sched/reschedule').single),
          {'patientRef': 'SYN-75-028B-381-05', 'plannedAt': apiDay(2), 'reason': 'Пациент попросил позже'});
      expect(find.text('Дата перенесена'), findsOneWidget);
    });

    testWidgets('reschedule of an overdue referral: the past date is outside the window, so a new date must be picked', (tester) async {
      await receiving(tester);
      await tapAction(tester, 'd-over', 'Перенести');
      expect(find.text(routeDate(apiDay(-5))), findsOneWidget);
      await tester.enterText(sheetText, 'Пациент заболел');
      await tester.pump();
      expect(enabled(tester, submit), isFalse, reason: 'как в вебе: дата вне окна — кнопка выключена');
    });

    testWidgets('discharge: the summary is required; body {patientRef, summary}', (tester) async {
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-adm/discharge': recorded()});
      await tapAction(tester, 'd-adm', 'Выписать');
      expect(find.text('Эпикриз выписки'), findsOneWidget);
      expect(find.text('Что написать направившему врачу'), findsOneWidget);
      expect(enabled(tester, submit), isFalse);
      await tester.enterText(sheetText, 'Факоэмульсификация, наблюдение через 7 дней');
      await tester.pump();
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(bodyOf(backend.calls('POST', '/journal/referrals/d-adm/discharge').single),
          {'patientRef': 'SYN-75-028B-381-08', 'summary': 'Факоэмульсификация, наблюдение через 7 дней'});
      expect(find.text('Пациент выписан'), findsOneWidget);
    });
  });

  group('admitted and did not come ask first (Q-13)', () {
    testWidgets('«Госпитализирован»: cancel sends nothing; confirm sends {patientRef} once and shows the toast', (tester) async {
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-today/admit': recorded()});
      await tapAction(tester, 'd-today', 'Госпитализирован');
      expect(find.text('Пациент госпитализирован?'), findsOneWidget);
      expect(find.text('Отметка попадёт в журнал маршрута, дальше останется только выписка.'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await pumpFrames(tester);
      expect(backend.calls('POST', '/journal/referrals/d-today/admit'), isEmpty);

      await tapAction(tester, 'd-today', 'Госпитализирован');
      await tester.tap(askConfirm);
      await pumpFrames(tester);
      expect(bodyOf(backend.calls('POST', '/journal/referrals/d-today/admit').single), {'patientRef': 'SYN-75-028B-381-06'});
      expect(find.text('Госпитализация отмечена'), findsOneWidget);
      expect(backend.calls('GET', '/journal/referrals/incoming'), hasLength(2));
    });

    testWidgets('«Не пришёл»: the question explains the route closes; confirm sends {patientRef}', (tester) async {
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-over/no-show': recorded()});
      await tapAction(tester, 'd-over', 'Не пришёл');
      expect(find.text('Пациент не пришёл?'), findsOneWidget);
      expect(find.textContaining('Маршрут закроется'), findsOneWidget);
      await tester.tap(askConfirm);
      await pumpFrames(tester);
      expect(bodyOf(backend.calls('POST', '/journal/referrals/d-over/no-show').single), {'patientRef': 'SYN-75-22GN-152-07'});
      expect(find.text('Неявка отмечена'), findsOneWidget);
    });

    testWidgets('while a mark is in flight every action button is disabled; afterwards they come back', (tester) async {
      final pending = Completer<http.Response>();
      await receiving(tester, extra: {'POST /journal/referrals/d-today/admit': (http.Request _) => pending.future});
      await tapAction(tester, 'd-today', 'Госпитализирован');
      await tester.tap(askConfirm);
      await pumpFrames(tester);
      expect(enabled(tester, actionButton('d-sev', 'Подтвердить приём')), isFalse);
      expect(enabled(tester, actionButton('d-over', 'Не пришёл')), isFalse);
      expect(inCard('d-today', find.byType(LinearProgressIndicator)), findsOneWidget);
      pending.complete(recorded());
      await pumpFrames(tester);
      expect(enabled(tester, actionButton('d-sev', 'Подтвердить приём')), isTrue);
    });

    testWidgets('403 on a mark → the no-access reason in a snackbar, never «Сервер недоступен»', (tester) async {
      await receiving(tester, extra: {'POST /journal/referrals/d-today/admit': problem(403, 'Forbidden', detail: 'no_organization')});
      await tapAction(tester, 'd-today', 'Госпитализирован');
      await tester.tap(askConfirm);
      await pumpFrames(tester);
      expect(find.text('К учётной записи не привязана организация: раздел откроется, когда администратор её укажет.'), findsOneWidget);
      expect(find.textContaining('Сервер недоступен'), findsNothing);
    });
  });

  group('errors follow one recipe', () {
    testWidgets('409: the list is reloaded first, then «title — detail»; the sheet closes and the card shows the new state', (tester) async {
      final (_, backend) = await receiving(tester, extra: {
        'POST /journal/referrals/d-sev/confirm': problem(409, 'Пациент ещё не согласился',
            detail: 'нельзя подтвердить приём, пока пациент не принял перевод', stateCode: 'transfer_pending_consent'),
      });
      final changed = [
        incomingJson('d-sev', ref: 'SYN-75-028B-381-03', severe: true, consent: 'pending', status: 'transfer_pending_consent'),
        ...demoIncoming().skip(1),
      ];
      await tapAction(tester, 'd-sev', 'Подтвердить приём');
      backend.routes['/journal/referrals/incoming'] = changed;
      await tester.tap(submit);
      await pumpFrames(tester);

      final paths = [for (final r in backend.requests) '${r.method} ${r.url.path}'];
      final post = paths.indexOf('POST /api/v1/journal/referrals/d-sev/confirm');
      expect(paths.lastIndexOf('GET /api/v1/journal/referrals/incoming'), greaterThan(post), reason: '409 → сначала перечитать список');
      expect(find.text('Пациент ещё не согласился — нельзя подтвердить приём, пока пациент не принял перевод'), findsOneWidget);
      expect(submit, findsNothing);
      expect(inCard('d-sev', find.text('действий нет')), findsOneWidget);
    });

    testWidgets('404 (the transfer is gone): reload, close the sheet, show the server text', (tester) async {
      final (_, backend) = await receiving(tester, extra: {
        'POST /journal/referrals/d-adm/discharge':
            problem(404, 'Направление не найдено', detail: 'нет действующего перевода этого пациента в вашу организацию с таким decisionId'),
      });
      await tapAction(tester, 'd-adm', 'Выписать');
      await tester.enterText(sheetText, 'Эпикриз');
      await tester.pump();
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(backend.calls('GET', '/journal/referrals/incoming'), hasLength(2));
      expect(find.textContaining('Направление не найдено'), findsOneWidget);
      expect(submit, findsNothing);
    });

    testWidgets('422 plannedAt: the message sits under the date field, the sheet stays, no snackbar', (tester) async {
      await receiving(tester, extra: {
        'POST /journal/referrals/d-sev/confirm': problem(422, 'Ошибка валидации', errors: {
          'plannedAt': ['дата госпитализации — с 02.10.2026 по 01.11.2026'],
        }),
      });
      await tapAction(tester, 'd-sev', 'Подтвердить приём');
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(submit, findsOneWidget, reason: 'лист открыт');
      final message = find.text('дата госпитализации — с 02.10.2026 по 01.11.2026');
      expect(message, findsOneWidget);
      expect(find.descendant(of: sheetDate, matching: message), findsOneWidget, reason: 'под полем даты');
      expect(find.byType(SnackBar), findsNothing);
      expect(enabled(tester, submit), isTrue);
    });

    testWidgets('422 reason: the message sits under the text field', (tester) async {
      await receiving(tester, extra: {
        'POST /journal/referrals/d-sev/reject': problem(422, 'Ошибка валидации', errors: {
          'reason': ['обязательное поле'],
        }),
      });
      await tapAction(tester, 'd-sev', 'Отказать');
      await tester.enterText(sheetText, 'x');
      await tester.pump();
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(find.descendant(of: sheetText, matching: find.text('обязательное поле')), findsOneWidget);
    });

    testWidgets('network failure: «Сервер недоступен» inside the sheet; the next tap goes with a new key', (tester) async {
      final (_, backend) = await receiving(tester, extra: {
        'POST /journal/referrals/d-sev/confirm': (http.Request _) => throw http.ClientException('connection refused'),
      });
      await tapAction(tester, 'd-sev', 'Подтвердить приём');
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(find.text('Сервер недоступен. Повторите попытку позже.'), findsOneWidget);
      expect(find.textContaining('connection refused'), findsNothing, reason: 'без текста исключения');
      expect(enabled(tester, submit), isTrue);
      await tester.tap(submit);
      await pumpFrames(tester);
      final posts = backend.calls('POST', '/journal/referrals/d-sev/confirm');
      expect(posts, hasLength(2));
      expect(posts[0].headers['Idempotency-Key'], isNot(posts[1].headers['Idempotency-Key']), reason: 'новый ключ на каждое нажатие');
    });

    testWidgets('a double tap on the sheet button writes one record', (tester) async {
      final pending = Completer<http.Response>();
      final (_, backend) = await receiving(tester, extra: {'POST /journal/referrals/d-sev/confirm': (http.Request _) => pending.future});
      await tapAction(tester, 'd-sev', 'Подтвердить приём');
      await tester.tap(submit);
      await tester.tap(submit, warnIfMissed: false);
      await tester.pump();
      expect(enabled(tester, submit), isFalse, reason: 'кнопка выключена, пока запрос в полёте');
      pending.complete(recorded());
      await pumpFrames(tester);
      expect(backend.calls('POST', '/journal/referrals/d-sev/confirm'), hasLength(1));
    });
  });

  testWidgets('the «Входящие» tab badge follows a confirmation (bell refreshed after the action)', (tester) async {
    final (session, backend) = await demoSession(DemoUser.doctor2, api: receivingApi(pending: 1));
    backend.routes['POST /journal/referrals/d-sev/confirm'] = (http.Request _) {
      backend.routes['/journal/notifications/bell'] = {'pendingIncomingCount': 0};
      return recorded();
    };
    await pumpRouterApp(tester, session, location: '/doctor/incoming', size: tallPhone);
    final badge = find.descendant(of: find.byType(FloatingNav), matching: find.byKey(CountBadge.pillKey));
    expect(badge, findsOneWidget);
    await tapAction(tester, 'd-sev', 'Подтвердить приём');
    await tester.tap(submit);
    await pumpFrames(tester);
    expect(badge, findsNothing);
  });

  testWidgets('sheets open above the tab pill: a tap where the pill is does not switch tabs under an open sheet', (tester) async {
    final (session, _) = await demoSession(DemoUser.doctor2, api: receivingApi());
    final router = await pumpRouterApp(tester, session, location: '/doctor/incoming', size: const Size(390, 900));
    final patientsTab = tester.getCenter(find.descendant(of: find.byType(FloatingNav), matching: find.text('Пациенты')));
    await tapAction(tester, 'd-sev', 'Подтвердить приём');
    expect(submit, findsOneWidget);
    await tester.tapAt(patientsTab);
    await pumpFrames(tester);
    expect(router.state.uri.path, '/doctor/incoming');
  });

  group('Kazakh', () {
    testWidgets('sheets and the question in Kazakh at 1.3 on a 360 dp phone, without overflow', (tester) async {
      await receiving(tester, locale: 'kk', textScale: 1.3, size: tallNarrow);
      await tapAction(tester, 'd-sev', 'Қабылдауды растау');
      expect(find.text('Бүгіннен ерте емес және 30 күннен кеш емес'), findsOneWidget);
      expect(find.text('Түсініктеме (міндетті емес)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Болдырмау'));
      await pumpFrames(tester);

      await tapAction(tester, 'd-adm', 'Шығару');
      expect(find.text('Шығару эпикризі'), findsOneWidget);
      expect(find.text('Жіберген дәрігерге не жазу керек'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Болдырмау'));
      await pumpFrames(tester);

      await tapAction(tester, 'd-over', 'Келмеді');
      expect(find.text('Пациент келмеді ме?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('success toast and server texts in the Kazakh UI', (tester) async {
      await receiving(tester, locale: 'kk', extra: {'POST /journal/referrals/d-sev/reject': recorded()});
      await tapAction(tester, 'd-sev', 'Бас тарту');
      expect(find.text('Қабылдаудан бас тарту'), findsOneWidget);
      await tester.enterText(sheetText, 'Орын жоқ');
      await tester.pump();
      await tester.tap(submit);
      await pumpFrames(tester);
      expect(find.text('Бас тарту жазылды'), findsOneWidget);
    });
  });

  testWidgets('a user without referral.confirm sees no buttons even when the server lists actions', (tester) async {
    final item = IncomingReferral.fromJson(incomingJson('d-x', allowed: ['confirm', 'reject']));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: IncomingCard(item: item, canAct: false, onAction: (_) => fail('кнопок быть не должно'))),
    ));
    expect(find.text('Подтвердить приём'), findsNothing);
    expect(find.text('действий нет'), findsOneWidget);
  });
}
