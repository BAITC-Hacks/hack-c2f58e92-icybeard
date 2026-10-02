import 'dart:io';

import 'package:darumen/l10n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Словарь экранов гражданина (strings_citizen.dart): тексты, которые есть в вебе, — дословно из
/// apps/web/src/i18n/{ru,kk}.ts (строка с плейсхолдерами vue-i18n должна встречаться там в одинарных кавычках);
/// тексты уведомлений — по всем 13 видам колокольчика гражданина в двух языках.
final ru = S.of('ru');
final kk = S.of('kk');
final webRu = File('../web/src/i18n/ru.ts').readAsStringSync();
final webKk = File('../web/src/i18n/kk.ts').readAsStringSync();

void expectWeb(String text, {required bool kazakh}) =>
    expect(kazakh ? webKk : webRu, contains("'$text'"), reason: '«$text» должна быть дословно в ${kazakh ? 'kk' : 'ru'}.ts');

/// Строка словаря и ключ веба, по которому она сверяется.
typedef Pair = (String Function(S s), String key);

void main() {
  test('every citizen string that exists on the web is copied verbatim in both languages', () {
    final pairs = <Pair>[
      ((s) => s.myHospital, 'route.citizen.yourHospital'),
      ((s) => s.myFactSince, 'route.citizen.factSince'),
      ((s) => s.myFactWaiting, 'route.citizen.factWaiting'),
      ((s) => s.myFactDays(7).replaceAll('7', '{days}'), 'route.citizen.factDays'),
      ((s) => s.myFactAsOf, 'route.citizen.factAsOf'),
      ((s) => s.myRouteNotFound, 'route.notFound'),
      ((s) => s.myWhatNext, 'route.whatNext'),
      ((s) => s.myDatePlanned, 'route.dates.planned'),
      ((s) => s.myDateExpected, 'route.dates.expected'),
      ((s) => s.myUpdateTests(7).replaceAll('7', '{n}'), 'route.updateTests'),
      ((s) => s.myValidTests(7).replaceAll('7', '{n}'), 'route.validTests'),
      ((s) => s.myNormLabel, 'route.normLabel'),
      ((s) => s.myForecastLead, 'route.citizen.forecastLead'),
      ((s) => s.myForecastNine('{days}'), 'route.citizen.forecastNine'),
      ((s) => s.myForecastWithin30('{pct}'), 'route.citizen.forecastWithin30'),
      ((s) => s.myBenchmarkSource('{source}'), 'route.citizen.benchmarkSource'),
      ((s) => s.myProposedBody('{name}'), 'route.citizen.proposedBody'),
      ((s) => s.myDoctorReason('{reason}'), 'route.doctorReason'),
      ((s) => s.myConsentAccept, 'route.consentAccept'),
      ((s) => s.myConsentDecline, 'route.consentDecline'),
      ((s) => s.myWaitConfirmTitle, 'route.citizen.waitConfirmTitle'),
      ((s) => s.myWaitConfirmBody('{name}'), 'route.citizen.waitConfirmBody'),
      ((s) => s.myWithdrawConsent, 'route.citizen.withdrawConsent'),
      ((s) => s.myTransferredTitle, 'route.citizen.transferredTitle'),
      ((s) => s.myTransferredBody('{name}', '{date}'), 'route.citizen.transferredBody'),
      ((s) => s.myOverdueBody, 'route.citizen.overdueBody'),
      ((s) => s.myRefuseHospital, 'route.citizen.refuseHospital'),
      ((s) => s.myAdmittedTitle, 'route.citizen.admittedTitle'),
      ((s) => s.myWithdrawalTitle, 'route.citizen.withdrawalTitle'),
      ((s) => s.myWithdrawalBody, 'route.citizen.withdrawalBody'),
      ((s) => s.myStillWaiting, 'route.citizen.stillWaiting'),
      ((s) => s.myDoctorSuggested, 'route.doctorSuggested'),
      ((s) => s.myDoctorKept, 'route.keep'),
      ((s) => s.myHalfWaits, 'hero.half'),
      ((s) => s.myCompareWait, 'route.compareWait'),
      ((s) => s.myFasterTitle, 'route.whereFaster'),
      ((s) => s.myFasterLead, 'route.citizen.fasterLead'),
      ((s) => s.myRequestsClosed, 'route.citizen.requestsClosed'),
      ((s) => s.myStayTitle, 'route.citizen.stayTitle'),
      ((s) => s.myStay, 'route.citizen.stay'),
      ((s) => s.myStayDone, 'route.citizen.stayDone'),
      ((s) => s.myStayHint, 'route.citizen.stayHint'),
      ((s) => s.myCommentLabel, 'route.citizen.commentLabel'),
      ((s) => s.myCommentHint, 'route.citizen.commentHint'),
      ((s) => s.myScribeAskTitle, 'route.citizen.scribeAskTitle'),
      ((s) => s.myScribeAskBody('{org}'), 'route.citizen.scribeAskBody'),
      ((s) => s.myScribeAllow, 'route.citizen.scribeAllow'),
      ((s) => s.myScribeDeny, 'route.citizen.scribeDeny'),
      ((s) => s.myScribeAllowed, 'route.citizen.scribeAllowed'),
      ((s) => s.myScribeWithdraw, 'route.citizen.scribeWithdraw'),
      ((s) => s.myScribeAnswered, 'route.citizen.scribeAnswered'),
      ((s) => s.myLeafletsTitle, 'route.citizen.leafletsTitle'),
      ((s) => s.myLeafletOpen, 'route.citizen.leafletOpen'),
      ((s) => s.myLeafletApprovedOn('{date}'), 'leaflet.approvedOn'),
      ((s) => s.myLeafletApprovedBy, 'leaflet.approvedBy'),
      ((s) => s.myLeafletTalked, 'leaflet.talked'),
      ((s) => s.myLeafletFooter, 'leaflet.footer'),
      ((s) => s.myLeafletAudioDeleted, 'leaflet.audioDeleted'),
      ((s) => s.myLeafletNoPersona, 'leaflet.noPersona'),
      ((s) => s.myLeafletSynthetic, 'leaflet.synthetic'),
      ((s) => s.myLeafletExpiredTitle, 'leaflet.expiredTitle'),
      ((s) => s.myLeafletExpiredText, 'leaflet.expiredText'),
      ((s) => s.myCopyLink, 'shell.copyLink'),
      ((s) => s.myLinkCopied, 'shell.copied'),
      ((s) => s.routeSyntheticNote('{asOf}'), 'route.synthetic'),
      ((s) => s.myNeedsAnswer, 'bell.citizen.needsAction'),
    ];
    for (final (text, key) in pairs) {
      expect(text(ru), isNot(text(kk)), reason: '$key: казахский текст не должен совпадать с русским');
      expectWeb(text(ru), kazakh: false);
      expectWeb(text(kk), kazakh: true);
    }
  });

  group('notification texts of the citizen bell', () {
    const kinds = [
      'scribe_consent',
      'scribe_leaflet',
      'redirect',
      'keep',
      'cancel',
      'confirm',
      'reject',
      'reschedule',
      'admit',
      'no_show',
      'discharge',
      'close',
      'tests_expiring',
    ];

    test('all 13 kinds are bell.citizen.* of the web, verbatim, with {org}, {date} and {count}', () {
      for (final s in [ru, kk]) {
        for (final kind in kinds) {
          final text = s.myNotificationText(kind, name: '{org}', date: '{date}', count: 7, needsAction: true).replaceAll('7', '{count}');
          expectWeb(text, kazakh: s.locale == 'kk');
        }
      }
    });

    test('a redirect that no longer needs an answer reads «Врач предложил перевод: …» (Q15)', () {
      expect(ru.myNotificationText('redirect', name: 'Достар Мед', needsAction: true), 'Врач предлагает перевод: Достар Мед. Нужен ваш ответ');
      expect(ru.myNotificationText('redirect', name: 'Достар Мед'), 'Врач предложил перевод: Достар Мед');
      expect(kk.myNotificationText('redirect', name: 'Достар Мед'), 'Дәрігер ауыстыруды ұсынды: Достар Мед');
    });

    test('the bell texts that equal the journal come from the route kit, not from a second copy', () {
      for (final kind in ['keep', 'cancel', 'reject', 'admit', 'no_show', 'discharge', 'close']) {
        for (final s in [ru, kk]) {
          expect(s.myNotificationText(kind, name: 'X'), s.routeJournalTitle(kind, RouteVoice.citizen, name: 'X'), reason: kind);
        }
      }
    });

    test('an unknown kind falls back to its code and never throws', () {
      expect(ru.myNotificationText('something_new'), 'something_new');
    });
  });

  test('new copy without a web counterpart exists in both languages and differs between them', () {
    final texts = <String Function(S s)>[
      (s) => s.myConfirmWithdrawTitle,
      (s) => s.myConfirmRefuseTitle,
      (s) => s.myConfirmDeclineTitle,
      (s) => s.myConfirmDeclineBody('Достар Мед'),
      (s) => s.myConfirmWithdrawConsentTitle,
      (s) => s.myConfirmWithdrawConsentBody,
      (s) => s.myOpenInBrowser,
    ];
    for (final text in texts) {
      expect(text(ru), isNotEmpty);
      expect(text(kk), isNotEmpty);
      expect(text(ru), isNot(text(kk)));
    }
    expect(ru.myConfirmDeclineBody('Достар Мед'), contains('Достар Мед'));
    expect(kk.myConfirmDeclineBody('Достар Мед'), contains('Достар Мед'));
  });
}
