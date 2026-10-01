import 'dart:io';

import 'package:darumen/l10n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Словарь принимающей больницы и колокольчика персонала (strings_incoming.dart): тексты, которые есть в вебе,
/// дословно из apps/web/src/i18n/{ru,kk}.ts (проверка по самому файлу веба: значение в одинарных кавычках, с
/// плейсхолдерами vue-i18n); свои тексты телефона (подтверждение перед «Госпитализирован» и «Не пришёл», состояние без
/// больницы со ссылкой на веб) — в обоих языках и не пустые.
final ru = S.of('ru');
final kk = S.of('kk');
final webRu = File('../web/src/i18n/ru.ts').readAsStringSync();
final webKk = File('../web/src/i18n/kk.ts').readAsStringSync();

void expectWeb(String text, {required bool kazakh}) =>
    expect(kazakh ? webKk : webRu, contains("'$text'"), reason: '«$text» должна быть дословно в ${kazakh ? 'kk' : 'ru'}.ts');

void expectBoth(String Function(S s) pick) {
  expectWeb(pick(ru), kazakh: false);
  expectWeb(pick(kk), kazakh: true);
}

const patientEventKinds = [
  'request',
  'prefer_current',
  'still_waiting',
  'withdraw',
  'treated_elsewhere',
  'consent_accepted',
  'consent_declined',
  'scribe_granted',
  'scribe_declined',
  'scribe_withdrawn',
];

void main() {
  group('входящие направления — doctor.incoming.* веба', () {
    test('шапка, этапы фильтра, тяжесть, поиск и подсказки', () {
      expectBoth((s) => s.incomingSubtitle);
      expectBoth((s) => s.incomingNoOrgTitle);
      for (final stage in ['all', 'consent', 'confirm', 'scheduled', 'admitted', 'closed']) {
        expectBoth((s) => s.incomingStageLabel(stage));
      }
      expect(ru.incomingStageLabel('something_new'), 'Все этапы', reason: 'незнакомый этап — «все»');
      expectBoth((s) => s.incomingStageField);
      expectBoth((s) => s.incomingSevereOnly);
      expectBoth((s) => s.incomingSearchHint);
      expectBoth((s) => s.incomingOverdue);
      expectBoth((s) => s.incomingNote);
    });

    test('кнопки, отметка «Выписан» и «действий нет»', () {
      expectBoth((s) => s.incomingConfirmAction);
      expectBoth((s) => s.incomingRejectAction);
      expectBoth((s) => s.incomingAdmitAction);
      expectBoth((s) => s.incomingDischargeAction);
      expectBoth((s) => s.incomingRescheduleAction);
      expectBoth((s) => s.incomingNoShowAction);
      expectBoth((s) => s.incomingDischargedMark);
      expectBoth((s) => s.incomingNoActions);
      expect(ru.incomingAdmitAction, 'Госпитализирован');
      expect(kk.incomingNoShowAction, 'Келмеді');
    });

    test('листы действий: заголовки, поля, подсказка окна дат и тосты успеха', () {
      expectBoth((s) => s.incomingConfirmTitle);
      expectBoth((s) => s.incomingRejectTitle);
      expectBoth((s) => s.incomingRescheduleTitle);
      expectBoth((s) => s.incomingDischargeTitle);
      expectBoth((s) => s.incomingPlannedAt);
      expectBoth((s) => s.incomingPlannedHint);
      expectBoth((s) => s.incomingComment);
      expectBoth((s) => s.incomingRejectReason);
      expectBoth((s) => s.incomingRescheduleReason);
      expectBoth((s) => s.incomingDischargeSummary);
      expectBoth((s) => s.incomingDischargePlaceholder);
      expectBoth((s) => s.incomingConfirmedDone);
      expectBoth((s) => s.incomingRejectedDone);
      expectBoth((s) => s.incomingRescheduledDone);
      expectBoth((s) => s.incomingDischargedDone);
      expectBoth((s) => s.incomingAdmittedDone);
      expectBoth((s) => s.incomingNoShowDone);
    });

    test('«показаны N из M» — doctor.worklist.shown веба с плейсхолдерами', () {
      expectWeb(ru.incomingShown(7, 9).replaceAll('7', '{shown}').replaceAll('9', '{total}'), kazakh: false);
      expectWeb(kk.incomingShown(7, 9).replaceAll('7', '{shown}').replaceAll('9', '{total}'), kazakh: true);
    });

    test('число направлений: «{n} направлений» веба, по-русски — с согласованием (1 направление, 2 направления)', () {
      expectWeb(ru.incomingTotal(5).replaceAll('5', '{n}'), kazakh: false);
      expectWeb(kk.incomingTotal(5).replaceAll('5', '{n}'), kazakh: true);
      expect(ru.incomingTotal(1), '1 направление');
      expect(ru.incomingTotal(3), '3 направления');
      expect(ru.incomingTotal(11), '11 направлений');
      expect(ru.incomingTotal(21), '21 направление');
      expect(ru.incomingTotal(0), '0 направлений');
      expect(kk.incomingTotal(1), '1 жолдама');
    });

    test('свои тексты телефона: без больницы (Q-2) и подтверждение необратимых отметок (Q-13) — в обоих языках', () {
      for (final pick in <String Function(S)>[
        (s) => s.incomingNoOrgBody,
        (s) => s.incomingAdmitAsk,
        (s) => s.incomingAdmitAskBody,
        (s) => s.incomingNoShowAsk,
        (s) => s.incomingNoShowAskBody,
      ]) {
        expect(pick(ru), isNotEmpty);
        expect(pick(kk), isNotEmpty);
        expect(pick(ru), isNot(pick(kk)));
      }
      expect(ru.incomingNoOrgBody, startsWith('Входящие направления есть у конкретной больницы.'), reason: 'первая фраза — дословно веб noOrgText');
      expect(kk.incomingNoOrgBody, startsWith('Кіріс жолдамалар нақты ауруханада болады.'));
    });
  });

  group('уведомления персонала — bell.* веба', () {
    test('подтверждение и выписка по моим направлениям', () {
      expectBoth((s) => s.staffBellConfirmed('{org}'));
      expectBoth((s) => s.staffBellDischarged('{org}'));
    });

    test('все десять событий пациента; незнакомое событие — запасная подпись с рефом, без сырого кода', () {
      for (final kind in patientEventKinds) {
        expectBoth((s) => s.staffBellPatientEvent(kind, ref: '{ref}', org: '{org}'));
      }
      final fallback = ru.staffBellPatientEvent('something_new', ref: 'SYN-75-028B-381-01', org: '');
      expect(fallback, contains('SYN-75-028B-381-01'));
      expect(fallback, isNot(contains('something_new')));
      expect(kk.staffBellPatientEvent('something_new', ref: 'SYN-1', org: ''), contains('SYN-1'));
    });
  });
}
