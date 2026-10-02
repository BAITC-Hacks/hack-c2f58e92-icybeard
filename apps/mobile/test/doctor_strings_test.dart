import 'dart:io';

import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Словарь экранов врача (strings_doctor.dart): рабочий список и маршрут пациента. Каждая строка, у которой есть
/// пара в вебе, дословно совпадает с apps/web/src/i18n/{ru,kk}.ts — проверяется по самим файлам веба.
final ru = S.of('ru');
final kk = S.of('kk');
final webRu = File('../web/src/i18n/ru.ts').readAsStringSync();
final webKk = File('../web/src/i18n/kk.ts').readAsStringSync();

void expectWeb(String text, {required bool kazakh}) =>
    expect(kazakh ? webKk : webRu, contains("'$text'"), reason: '«$text» должна быть дословно в ${kazakh ? 'kk' : 'ru'}.ts');

/// Обе локали строки — дословно из веба.
void expectBoth(String Function(S s) pick) {
  expectWeb(pick(ru), kazakh: false);
  expectWeb(pick(kk), kazakh: true);
}

/// Числа и имена-заглушки заменяются плейсхолдерами vue-i18n: так параметризованные строки сверяются с вебом.
String placeholders(String text, Map<String, String> names) => names.entries.fold(text, (acc, e) => acc.replaceAll(e.key, '{${e.value}}'));

void main() {
  group('рабочий список', () {
    test('восемь флагов — route.flags.* веба, незнакомый флаг — сам код', () {
      for (final flag in RouteCodes.riskFlags) {
        expectBoth((s) => s.worklistFlag(flag));
      }
      expect(ru.worklistFlag(RouteCodes.flagTransferredIn), 'переведён к нам');
      expect(kk.worklistFlag(RouteCodes.flagDateOverdue), 'күн өтті');
      expect(ru.worklistFlag('new_flag'), 'new_flag');
    });

    test('девять пунктов фильтра — doctor.worklist.filter.*, со счётчиком через « · »', () {
      for (final code in ['all', ...RouteCodes.riskFlags]) {
        expectBoth((s) => s.worklistFilter(code));
      }
      expect(ru.worklistFilterOption('all', 60), 'Все пациенты · 60');
      expect(kk.worklistFilterOption(RouteCodes.flagRefusalRisk, 7), 'Бас тарту қаупі жоғары · 7');
      expect(ru.worklistFilter('mystery'), 'mystery');
    });

    test('четырнадцать следующих шагов — короткие и полные подписи веба в обоих языках', () {
      expect(RouteCodes.nextActions, hasLength(14));
      for (final code in RouteCodes.nextActions) {
        expectBoth((s) => s.worklistNextShort(code));
        expectBoth((s) => s.worklistNextFull(code));
      }
      expect(ru.worklistNextShort(RouteCodes.nextReviewBeforeCall), 'проверить документы');
      expect(kk.worklistNextFull(RouteCodes.nextConfirmWithdrawal), 'күту парағынан шығаруды растау');
    });

    test('незнакомый или пустой код шага — русская подпись API как есть, без неё — пусто', () {
      expect(ru.worklistNextShort('', fallback: 'ждать вызова'), 'ждать вызова');
      expect(kk.worklistNextFull('future_code', fallback: 'новый шаг'), 'новый шаг');
      expect(ru.worklistNextShort('future_code'), '');
    });

    test('этап строки без флагов — doctor.worklist.stageCode.*, незнакомый — подпись API', () {
      for (final code in ['registered', 'waiting', 'called']) {
        expectBoth((s) => s.worklistStage(code));
      }
      expect(ru.worklistStage('other', fallback: 'на рассмотрении'), 'на рассмотрении');
    });

    test('сигнал пациента — route.patientSignal.* с коротким именем больницы, включая «хочет остаться»', () {
      for (final kind in RouteCodes.signalKinds) {
        expectWeb(placeholders(ru.worklistSignal(kind, name: 'NAME'), {'NAME': 'name'}), kazakh: false);
        expectWeb(placeholders(kk.worklistSignal(kind, name: 'NAME'), {'NAME': 'name'}), kazakh: true);
      }
      expect(ru.worklistSignal(RouteCodes.requestRedirect, name: 'Достар Мед'), 'Пациент просит рассмотреть: Достар Мед');
      expect(ru.worklistSignal(RouteCodes.preferCurrent), 'Пациент хочет остаться в своей больнице');
      expect(ru.worklistSignal('unknown'), 'unknown');
    });

    test('шапка, состояния и подписи списка — дословно из веба', () {
      for (final pick in <String Function(S)>[
        (s) => s.worklistPatients,
        (s) => s.worklistSubtitle,
        (s) => s.worklistSyntheticShort,
        (s) => s.worklistNote,
        (s) => s.worklistNoteFallback,
        (s) => s.worklistFlags,
        (s) => s.worklistSearch,
        (s) => s.worklistEmpty,
        (s) => s.worklistEmptyText,
        (s) => s.worklistEmptyFilter,
        (s) => s.worklistCreateReferral,
        (s) => s.worklistAssistant,
        (s) => s.worklistColumnPatient,
        (s) => s.worklistColumnDays,
        (s) => s.worklistColumnPriority,
      ]) {
        expectBoth(pick);
      }
      expectWeb(placeholders(ru.worklistShown(7, 60), {'7': 'shown', '60': 'total'}), kazakh: false);
      expectWeb(placeholders(kk.worklistShown(7, 60), {'7': 'shown', '60': 'total'}), kazakh: true);
      expectWeb(placeholders(ru.asOfLabel('31.03.2025'), {'31.03.2025': 'date'}), kazakh: false);
      expectWeb(placeholders(kk.asOfLabel('31.03.2025'), {'31.03.2025': 'date'}), kazakh: true);
    });
  });

  group('маршрут пациента', () {
    test('шапка, «Текущая больница» и «Что сделать» — route.doctorView.* и route.citizen.fact*', () {
      for (final pick in <String Function(S)>[
        (s) => s.patientRouteKicker,
        (s) => s.patientRouteRecordVisit,
        (s) => s.patientRouteSince,
        (s) => s.patientRouteWaiting,
        (s) => s.patientRouteAsOfFact,
        (s) => s.patientRouteCurrentHospital,
        (s) => s.patientRouteHalf,
        (s) => s.patientRouteNinety,
        (s) => s.patientRouteExpected,
        (s) => s.patientRouteRefusal,
        (s) => s.patientRouteTodo,
        (s) => s.patientRouteBasis,
        (s) => s.patientRouteNotFound,
        (s) => s.patientRouteWorklistLink,
      ]) {
        expectBoth(pick);
      }
      expectWeb(placeholders(ru.patientRouteDays(89), {'89': 'days'}), kazakh: false);
      expectWeb(placeholders(kk.patientRouteDays(89), {'89': 'days'}), kazakh: true);
    });

    test('карточка решения «Оставить или перевести» — подписи, кнопки и подсказки веба', () {
      for (final pick in <String Function(S)>[
        (s) => s.patientRouteWhereTitle,
        (s) => s.patientRouteRequested,
        (s) => s.patientRouteHalfShort,
        (s) => s.patientRouteReasonLabel,
        (s) => s.patientRouteRequired,
        (s) => s.patientRouteReasonExample,
        (s) => s.patientRouteSevere,
        (s) => s.patientRouteSevereOff,
        (s) => s.patientRouteKeep,
        (s) => s.patientRouteTransfer,
        (s) => s.patientRouteAssistantHint,
        (s) => s.patientRouteToAssistant,
        (s) => s.patientRouteReasonMissing,
        (s) => s.patientRoutePrefersCurrent,
      ]) {
        expectBoth(pick);
      }
      expectWeb(placeholders(ru.patientRouteAltNine('12'), {'12': 'days'}), kazakh: false);
      expectWeb(placeholders(kk.patientRouteAltNine('12'), {'12': 'days'}), kazakh: true);
      expectWeb(placeholders(ru.patientRouteAltRefusal('36 %'), {'36 %': 'pct'}), kazakh: false);
      expectWeb(placeholders(kk.patientRouteAltRefusal('36 %'), {'36 %': 'pct'}), kazakh: true);
    });

    test('карточка «Перевод» — route.progress.* веба', () {
      for (final pick in <String Function(S)>[
        (s) => s.patientRouteTransferTitle,
        (s) => s.patientRouteReason,
        (s) => s.patientRouteOverdue,
        (s) => s.patientRouteCancelReason,
        (s) => s.patientRouteCloseReason,
        (s) => s.patientRouteCancel,
        (s) => s.patientRouteClose,
        (s) => s.patientRouteCancelDone,
        (s) => s.patientRouteCloseDone,
        (s) => s.patientRouteToIncoming,
      ]) {
        expectBoth(pick);
      }
      expectWeb(placeholders(ru.patientRouteTransferTo('NAME'), {'NAME': 'name'}), kazakh: false);
      expectWeb(placeholders(kk.patientRouteTransferTo('NAME'), {'NAME': 'name'}), kazakh: true);
      expectWeb(placeholders(ru.patientRouteResponsible('NAME'), {'NAME': 'name'}), kazakh: false);
      expectWeb(placeholders(kk.patientRouteResponsible('NAME'), {'NAME': 'name'}), kazakh: true);
    });

    test('обязательное поле — «(обязательно)» после подписи', () {
      expect(ru.patientRouteRequiredLabel(ru.patientRouteReasonLabel), 'Причина решения (обязательно)');
      expect(kk.patientRouteRequiredLabel(kk.patientRouteCancelReason), 'Тоқтату себебі (міндетті)');
    });
  });
}
