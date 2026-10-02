import 'dart:io';

import 'package:darumen/l10n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Словарь маршрута (strings_route.dart): каждая семья кодов — одна функция со switch и запасной подписью; тексты
/// дословно из веб-словаря apps/web/src/i18n/{ru,kk}.ts (проверяется по самому файлу веба: строка с плейсхолдерами
/// vue-i18n должна встречаться в нём в одинарных кавычках).
const statuses = [
  'waiting',
  'kept',
  'transfer_pending_consent',
  'transfer_pending_confirmation',
  'transferred',
  'admitted',
  'withdrawal_requested',
  'closed',
];
const closedReasons = ['discharged', 'no_show', 'withdrawn', 'treated_elsewhere'];
const journalKinds = [
  'request',
  'prefer_current',
  'still_waiting',
  'withdraw',
  'treated_elsewhere',
  'keep',
  'redirect',
  'consent_accepted',
  'consent_declined',
  'confirm',
  'reject',
  'reschedule',
  'admit',
  'no_show',
  'discharge',
  'cancel',
  'close',
];
const citizenKinds = ['request', 'prefer_current', 'still_waiting', 'withdraw', 'treated_elsewhere', 'consent_accepted', 'consent_declined'];
const attemptOutcomes = ['declined', 'consent_withdrawn', 'cancelled', 'rejected', 'patient_withdrew', 'no_show'];
const roles = ['doctor', 'chief', 'org_admin', 'regulator', 'steward', 'auditor', 'admin', 'citizen'];

final ru = S.of('ru');
final kk = S.of('kk');
final webRu = File('../web/src/i18n/ru.ts').readAsStringSync();
final webKk = File('../web/src/i18n/kk.ts').readAsStringSync();

/// Текст встречается в веб-словаре дословно, как значение в одинарных кавычках.
void expectWeb(String text, {required bool kazakh}) =>
    expect(kazakh ? webKk : webRu, contains("'$text'"), reason: '«$text» должна быть дословно в ${kazakh ? 'kk' : 'ru'}.ts');

/// Числа-заглушки в готовой строке заменяются плейсхолдерами vue-i18n: так int-параметры сверяются с вебом.
String placeholders(String text, Map<int, String> names) =>
    names.entries.fold(text, (acc, e) => acc.replaceAll('${e.key}', '{${e.value}}'));

void main() {
  group('этапы маршрута', () {
    test('заголовок и счётчик этапов — route.stagesTitle / route.stagesCount', () {
      expectWeb(ru.routeStagesTitle, kazakh: false);
      expectWeb(kk.routeStagesTitle, kazakh: true);
      expect(ru.routeStagesCount(6, 3), '6 этапов · 3 пройдено');
      expect(kk.routeStagesCount(6, 3), '6 кезең · 3 өтілді');
    });
  });

  group('статус маршрута и причины закрытия', () {
    test('восемь статусов — route.progress.status.*, незнакомый — код', () {
      for (final status in statuses) {
        expectWeb(ru.routeStatusText(status), kazakh: false);
        expectWeb(kk.routeStatusText(status), kazakh: true);
      }
      expect(ru.routeStatusText('transfer_pending_consent'), 'Перевод предложен: ждём согласия пациента');
      expect(kk.routeStatusText('closed'), 'Бағыт аяқталды');
      expect(ru.routeStatusText('paused'), 'paused');
    });

    test('строка статуса для персонала дописывает причину закрытия через « · »', () {
      expect(ru.routeStatusLine('closed', closedReason: 'discharged'), 'Маршрут завершён · Выписан');
      expect(kk.routeStatusLine('closed', closedReason: 'withdrawn'), 'Бағыт аяқталды · Науқастың өтініші бойынша шығарылды');
      expect(ru.routeStatusLine('waiting'), 'В листе ожидания');
      expect(ru.routeStatusLine('waiting', closedReason: ''), 'В листе ожидания');
    });

    test('причины закрытия для персонала — route.progress.closed.* дословно', () {
      for (final reason in closedReasons) {
        expectWeb(ru.routeClosedReason(reason, RouteVoice.staff), kazakh: false);
        expectWeb(kk.routeClosedReason(reason, RouteVoice.staff), kazakh: true);
      }
      expect(ru.routeClosedReason('no_show', RouteVoice.staff), 'Не пришёл на госпитализацию');
      expect(ru.routeClosedReason('archived', RouteVoice.staff), 'archived');
    });

    test('гражданину — фразы журнала во втором лице, а без имени больницы — текст веба для персонала', () {
      expect(ru.routeClosedReason('discharged', RouteVoice.citizen, name: 'Онкоцентр'), 'Вы выписаны: Онкоцентр');
      expect(kk.routeClosedReason('no_show', RouteVoice.citizen, name: 'Онкоцентр'), 'Сіздің келмегеніңіз белгіленді: Онкоцентр');
      expect(ru.routeClosedReason('withdrawn', RouteVoice.citizen), 'Вас сняли с листа ожидания');
      expect(ru.routeClosedReason('treated_elsewhere', RouteVoice.citizen), 'Вы сообщили, что уже лечились');
      expect(ru.routeClosedReason('discharged', RouteVoice.citizen), 'Выписан');
      expect(ru.routeClosedReason('archived', RouteVoice.citizen), 'archived');
    });
  });

  group('журнал маршрута', () {
    test('17 видов записи в двух голосах — route.journal.citizen.* / doctor.* дословно, RU и KK', () {
      for (final voice in RouteVoice.values) {
        for (final kind in journalKinds) {
          expectWeb(ru.routeJournalTitle(kind, voice, name: '{name}'), kazakh: false);
          expectWeb(kk.routeJournalTitle(kind, voice, name: '{name}'), kazakh: true);
        }
        expect({for (final kind in journalKinds) ru.routeJournalTitle(kind, voice)}.length, 17, reason: 'у каждого вида своя фраза');
        expect({for (final kind in journalKinds) kk.routeJournalTitle(kind, voice)}.length, 17);
      }
    });

    test('голос выбирает лицо: гражданину «Вы…», персоналу «Пациент…»; имя подставляется', () {
      expect(ru.routeJournalTitle('request', RouteVoice.citizen, name: 'Достар Мед'), 'Вы попросили рассмотреть: Достар Мед');
      expect(ru.routeJournalTitle('request', RouteVoice.staff, name: 'Достар Мед'), 'Пациент просит рассмотреть: Достар Мед');
      expect(ru.routeJournalTitle('reject', RouteVoice.citizen, name: 'Достар Мед'), 'Достар Мед: не могут принять');
      expect(ru.routeJournalTitle('reject', RouteVoice.staff, name: 'Достар Мед'), 'Достар Мед: отказ в приёме');
      expect(kk.routeJournalTitle('admit', RouteVoice.citizen, name: 'Достар Мед'), 'Сіз емдеуге жатқызылдыңыз: Достар Мед');
      expect(kk.routeJournalTitle('close', RouteVoice.staff), 'Күту парағынан шығарылды');
    });

    test('незнакомый вид записи — сам код, а не пустая строка', () {
      expect(ru.routeJournalTitle('escalate', RouteVoice.citizen, name: 'X'), 'escalate');
      expect(kk.routeJournalTitle('escalate', RouteVoice.staff), 'escalate');
    });

    test('свои записи гражданина — семь видов; кто: «вы» / «пациент», иначе роль автора', () {
      for (final kind in journalKinds) {
        expect(routeJournalByCitizen(kind), citizenKinds.contains(kind), reason: kind);
      }
      expect(ru.routeJournalWho('request', 'citizen', RouteVoice.citizen), 'вы');
      expect(kk.routeJournalWho('request', 'citizen', RouteVoice.citizen), 'сіз');
      expect(ru.routeJournalWho('consent_declined', 'citizen', RouteVoice.staff), 'пациент');
      expect(ru.routeJournalWho('redirect', 'doctor', RouteVoice.citizen), 'врач');
      expect(kk.routeJournalWho('confirm', 'org_admin', RouteVoice.staff), 'ұйым әкімшісі');
    });

    test('роли автора — decision.role.* дословно; незнакомая — код, пустая — пусто', () {
      for (final role in roles) {
        expectWeb(ru.routeRoleShort(role), kazakh: false);
        expectWeb(kk.routeRoleShort(role), kazakh: true);
      }
      expect(ru.routeRoleShort('chief'), 'главврач');
      expect(ru.routeRoleShort('nurse'), 'nurse');
      expect(ru.routeRoleShort(''), '');
    });

    test('подпись плашки: «Причина» у решений, у своих записей — «Ваш комментарий» / «Комментарий пациента»', () {
      expect(ru.routeJournalNoteLabel('keep', RouteVoice.citizen), 'Причина');
      expect(ru.routeJournalNoteLabel('request', RouteVoice.citizen), 'Ваш комментарий');
      expect(ru.routeJournalNoteLabel('request', RouteVoice.staff), 'Комментарий пациента');
      expect(kk.routeJournalNoteLabel('reject', RouteVoice.staff), 'Себебі');
      expect(kk.routeJournalNoteLabel('withdraw', RouteVoice.citizen), 'Сіздің түсініктемеңіз');
    });

    test('заголовок ленты, пустая лента, назначенная дата и отметка тяжёлого случая — из веба', () {
      for (final dict in [ru, kk]) {
        final kazakh = dict == kk;
        expectWeb(dict.routeJournalHeading, kazakh: kazakh);
        expectWeb(dict.routeJournalEmpty, kazakh: kazakh);
        expectWeb(dict.routeJournalPlanned('{date}'), kazakh: kazakh);
        expectWeb(dict.routeSevereMark, kazakh: kazakh);
      }
      expect(ru.routeJournalHeading, 'Решения и запросы');
      expect(ru.routeJournalPlanned('05.10.2026'), 'Дата госпитализации: 05.10.2026');
    });
  });

  group('неудавшийся перевод', () {
    test('исходы для персонала — route.progress.attempt.* с именем больницы', () {
      for (final outcome in attemptOutcomes) {
        expectWeb(ru.routeAttemptText(outcome, RouteVoice.staff, name: '{name}'), kazakh: false);
        expectWeb(kk.routeAttemptText(outcome, RouteVoice.staff, name: '{name}'), kazakh: true);
      }
      expect(ru.routeAttemptText('rejected', RouteVoice.staff, name: 'Достар Мед'), 'Больница отказала в приёме: Достар Мед');
      expect(ru.routeAttemptText('patient_withdrew', RouteVoice.staff, name: 'X'), 'Пациент отказался от ожидания');
    });

    test('гражданину — фразы журнала во втором лице, отзыв согласия — «Согласие отозвано»', () {
      expect(ru.routeAttemptText('declined', RouteVoice.citizen, name: 'X'), 'Вы отказались от перевода');
      expect(ru.routeAttemptText('consent_withdrawn', RouteVoice.citizen, name: 'X'), 'Согласие отозвано');
      expect(ru.routeAttemptText('cancelled', RouteVoice.citizen, name: 'X'), 'Врач отменил перевод');
      expect(ru.routeAttemptText('rejected', RouteVoice.citizen, name: 'Достар Мед'), 'Достар Мед: не могут принять');
      expect(ru.routeAttemptText('patient_withdrew', RouteVoice.citizen), 'Вы сообщили, что госпитализация больше не нужна');
      expect(kk.routeAttemptText('no_show', RouteVoice.citizen, name: 'X'), 'Сіздің келмегеніңіз белгіленді: X');
      for (final outcome in attemptOutcomes) {
        expectWeb(ru.routeAttemptText(outcome, RouteVoice.citizen, name: '{name}'), kazakh: false);
        expectWeb(kk.routeAttemptText(outcome, RouteVoice.citizen, name: '{name}'), kazakh: true);
      }
    });

    test('незнакомый исход — «Перевод не состоялся» в обоих голосах, без логики на коде', () {
      for (final voice in RouteVoice.values) {
        expect(ru.routeAttemptText('expired', voice, name: 'X'), 'Перевод не состоялся');
        expect(kk.routeAttemptText('expired', voice), 'Ауыстыру болмады');
      }
      expectWeb(ru.routeAttemptTitle, kazakh: false);
      expectWeb(kk.routeLastAttempt, kazakh: true);
    });
  });

  group('согласие пациента на перевод', () {
    test('персоналу — route.consentStatus.*, гражданину — «Вы согласились / отказались от перевода»', () {
      for (final consent in ['pending', 'accepted', 'declined']) {
        for (final voice in RouteVoice.values) {
          expectWeb(ru.routeConsentState(consent, voice), kazakh: false);
          expectWeb(kk.routeConsentState(consent, voice), kazakh: true);
        }
      }
      expect(ru.routeConsentState('pending', RouteVoice.staff), 'ждём согласия пациента');
      expect(ru.routeConsentState('accepted', RouteVoice.citizen), 'Вы согласились на перевод', reason: 'один термин — «перевод» (Q19)');
      expect(ru.routeConsentState('declined', RouteVoice.citizen), 'Вы отказались от перевода');
      expect(ru.routeConsentState('pending', RouteVoice.citizen), 'Врач предлагает перевод');
      expect(kk.routeConsentState('accepted', RouteVoice.staff), 'пациент келісті');
      expect(ru.routeConsentState('revoked', RouteVoice.staff), 'revoked');
    });
  });

  group('приоритет 0…10', () {
    test('«N из 10» и название полосы — doctor.worklist.priorityOf / priorityLevel', () {
      expect(ru.priorityOutOfTen(8), '8 из 10');
      expect(kk.priorityOutOfTen(8), '10 ішінен 8');
      for (final band in PriorityBand.values) {
        expectWeb(ru.priorityBandName(band), kazakh: false);
        expectWeb(kk.priorityBandName(band), kazakh: true);
      }
      expect(ru.priorityBandName(PriorityBand.high), 'Высокий приоритет');
      expect(kk.priorityBandName(PriorityBand.low), 'Төмен басымдық');
      expect(ru.priorityHint(PriorityBand.mid, 5), 'Средний приоритет · 5 из 10');
    });
  });

  group('анализы и «Где быстрее»', () {
    test('группы чек-листа, счётчик, срок, даты, сноска и сводка — route.checklistGroup.* / checklistNote', () {
      for (final dict in [ru, kk]) {
        final kazakh = dict == kk;
        for (final status in ['expired', 'expiring', 'valid']) {
          expectWeb(dict.routeChecklistGroupTitle(status), kazakh: kazakh);
          expectWeb(dict.routeChecklistGroupHint(status), kazakh: kazakh);
        }
        expectWeb(placeholders(dict.routeChecklistCount(9876), {9876: 'n'}), kazakh: kazakh);
        expectWeb(dict.routeChecklistValidity('{label}'), kazakh: kazakh);
        expectWeb(dict.routeChecklistExpiredOn('{date}'), kazakh: kazakh);
        expectWeb(dict.routeChecklistValidTill('{date}'), kazakh: kazakh);
        expectWeb(dict.routeChecklistNote('{source}', '{date}'), kazakh: kazakh);
        expectWeb(placeholders(dict.routeChecklistSummary(9876, 5432), {9876: 'expired', 5432: 'valid'}), kazakh: kazakh);
        expectWeb(dict.routeNoData, kazakh: kazakh);
      }
      expect(ru.routeChecklistCount(3), 'анализов: 3');
      expect(ru.routeChecklistSummary(2, 5), 'истекли: 2 · действуют: 5');
      expect(ru.routeChecklistGroupTitle('lost'), 'lost');
    });

    test('плитка альтернативы: подводка, сравнение в трёх вариантах, сосед, чип и действие — из веба', () {
      for (final dict in [ru, kk]) {
        final kazakh = dict == kk;
        expectWeb(dict.routeTileLead, kazakh: kazakh);
        expectWeb(placeholders(dict.routeCompareFaster(9876), {9876: 'days'}), kazakh: kazakh);
        expectWeb(placeholders(dict.routeCompareSlower(9876), {9876: 'days'}), kazakh: kazakh);
        expectWeb(dict.routeCompareSame, kazakh: kazakh);
        expectWeb(dict.routeNeighbourRegion('{region}'), kazakh: kazakh);
        expectWeb(dict.routeRequestSent, kazakh: kazakh);
        expectWeb(dict.routeRequestConsider, kazakh: kazakh);
        expectWeb(dict.routeNoAlternatives, kazakh: kazakh);
      }
      expect(ru.routeCompareFaster(2), 'на 2 дн. меньше, чем в вашей больнице');
      expect(kk.routeCompareSlower(4), 'сіздің ауруханаңыздан 4 күн көп');
    });
  });
}
